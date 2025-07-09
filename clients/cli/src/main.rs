// 版权所有 (c) 2024 Nexus。保留所有权利。

mod analytics;
mod config;
mod consts;
mod environment;
mod error_classifier;
mod events;
mod keys;
mod logging;
mod memory_monitor;
mod dynamic_node_manager;
mod enhanced_display;
#[path = "proto/nexus.orchestrator.rs"]
mod nexus_orchestrator;
mod orchestrator;
mod pretty;
mod prover;
mod prover_runtime;
mod register;
pub mod system;
mod task;
mod task_cache;
mod ui;
mod workers;
mod node_list;

use crate::config::{Config, get_config_path};
use crate::environment::Environment;
use crate::orchestrator::{Orchestrator, OrchestratorClient};
use crate::prover_runtime::{start_anonymous_workers, start_authenticated_workers};
use crate::register::{register_node, register_user};
use crate::node_list::NodeList;

use clap::{ArgAction, Parser, Subcommand};
use crossterm::{
    event::{DisableMouseCapture, EnableMouseCapture},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ed25519_dalek::SigningKey;
use ratatui::{Terminal, backend::CrosstermBackend};
use std::{error::Error, io, sync::Arc};
use tokio::sync::broadcast;
use tokio::task::JoinSet;

// 固定行显示管理器
#[derive(Debug)]
struct FixedLineDisplay {
    #[allow(dead_code)]
    max_lines: usize,
    node_lines: Arc<tokio::sync::RwLock<std::collections::HashMap<u64, String>>>,
    last_render_hash: Arc<tokio::sync::Mutex<u64>>,
    proof_counts: Arc<tokio::sync::RwLock<std::collections::HashMap<u64, u64>>>,
    total_proofs: Arc<tokio::sync::RwLock<u64>>,
    start_time: chrono::DateTime<chrono::Local>,
}

impl FixedLineDisplay {
    fn new(max_lines: usize) -> Self {
        Self {
            max_lines,
            node_lines: Arc::new(tokio::sync::RwLock::new(std::collections::HashMap::with_capacity(max_lines))),
            last_render_hash: Arc::new(tokio::sync::Mutex::new(0)),
            proof_counts: Arc::new(tokio::sync::RwLock::new(std::collections::HashMap::new())),
            total_proofs: Arc::new(tokio::sync::RwLock::new(0)),
            start_time: chrono::Local::now(),
        }
    }

    async fn increment_proof_count(&self, node_id: u64) {
        let mut counts = self.proof_counts.write().await;
        let count = counts.entry(node_id).or_insert(0);
        *count += 1;

        let mut total = self.total_proofs.write().await;
        *total += 1;
    }

    async fn update_node_status(&self, node_id: u64, status: String) {
        // 检查是否是提交成功的状态
        if status.contains("Proof submitted") || status.contains("Successfully submitted proof") {
            self.increment_proof_count(node_id).await;
        }

        // 移除额外的时间戳，因为Event的Display实现已经包含了时间戳
        // 直接使用原始状态字符串
        let formatted_status = status;

        let needs_update = {
            let lines = self.node_lines.read().await;
            lines.get(&node_id) != Some(&formatted_status)
        };

        if needs_update {
            {
                let mut lines = self.node_lines.write().await;
                lines.insert(node_id, formatted_status.clone());
            }
            self.render_display_optimized().await;
        }
    }

    async fn render_display_optimized(&self) {
        let lines = self.node_lines.read().await;

        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        for (id, status) in lines.iter() {
            std::hash::Hasher::write_u64(&mut hasher, *id);
            std::hash::Hasher::write(&mut hasher, status.as_bytes());
        }
        let current_hash = std::hash::Hasher::finish(&mut hasher);

        let mut last_hash = self.last_render_hash.lock().await;
        if *last_hash != current_hash {
            *last_hash = current_hash;
            drop(last_hash);
            self.render_display(&lines).await;
        }
    }

    async fn render_display(&self, lines: &std::collections::HashMap<u64, String>) {
        // Clear screen and move to top
        print!("\x1b[2J\x1b[H");

        let start_time_str = self.start_time.format("%Y-%m-%d %H:%M:%S").to_string();

        // Title
        println!("🚀 Nexus Batch Mining Monitor - {}", start_time_str);
        println!("═══════════════════════════════════════");

        // Statistics
        let total_nodes = lines.len();
        let successful_count = lines.values()
            .filter(|status| status.contains("✅"))
            .count();
        let failed_count = lines.values()
            .filter(|status| status.contains("❌"))
            .count();
        let active_count = lines.values()
            .filter(|status| status.contains("🔄") || status.contains("⚠️"))
            .count();

        // 获取总证明数
        let total_proofs = *self.total_proofs.read().await;

        println!("📊 Status: {} Total | {} Active | {} Success | {} Failed",
                 total_nodes, active_count, successful_count, failed_count);
        println!("🎯 Total Proofs Submitted: {}", total_proofs);

        println!("───────────────────────────────────────");

        // Display sorted by node ID with proof counts
        let mut sorted_lines: Vec<_> = lines.iter().collect();
        sorted_lines.sort_by_key(|(id, _)| *id);

        let proof_counts = self.proof_counts.read().await;
        for (node_id, status) in sorted_lines {
            let proof_count = proof_counts.get(node_id).copied().unwrap_or(0);
            println!("Node-{} (Proofs: {}): {}", node_id, proof_count, status);
        }

        println!("───────────────────────────────────────");
        println!("💡 Press Ctrl+C to stop all miners");

        // Force output flush
        use std::io::Write;
        std::io::stdout().flush().unwrap();
    }
}

const MIN_WAIT_TIME: u64 = 5; // 最小等待时间（秒）
const MAX_WAIT_TIME: u64 = 30; // 最大等待时间（秒）
const INITIAL_WORKERS: u32 = 2; // 初始工作线程数
const MAX_WORKERS: u32 = 8; // 最大工作线程数

#[derive(Debug)]
struct AdaptiveConfig {
    wait_time: std::sync::atomic::AtomicU64,
    worker_count: std::sync::atomic::AtomicU32,
    success_count: std::sync::atomic::AtomicU32,
    failure_count: std::sync::atomic::AtomicU32,
}

impl AdaptiveConfig {
    fn new() -> Self {
        Self {
            wait_time: std::sync::atomic::AtomicU64::new(MIN_WAIT_TIME),
            worker_count: std::sync::atomic::AtomicU32::new(INITIAL_WORKERS),
            success_count: std::sync::atomic::AtomicU32::new(0),
            failure_count: std::sync::atomic::AtomicU32::new(0),
        }
    }

    fn adjust_wait_time(&self, queue_size: u32) {
        let current = self.wait_time.load(std::sync::atomic::Ordering::Relaxed);
        let new_wait_time = if queue_size == 0 {
            std::cmp::min(current * 2, MAX_WAIT_TIME)
        } else {
            std::cmp::max(current / 2, MIN_WAIT_TIME)
        };
        self.wait_time.store(new_wait_time, std::sync::atomic::Ordering::Relaxed);
    }

    fn adjust_worker_count(&self) {
        let success = self.success_count.load(std::sync::atomic::Ordering::Relaxed);
        let failure = self.failure_count.load(std::sync::atomic::Ordering::Relaxed);
        let current = self.worker_count.load(std::sync::atomic::Ordering::Relaxed);
        
        // 根据成功率调整工作线程数
        if success > failure && current < MAX_WORKERS {
            self.worker_count.store(std::cmp::min(current + 1, MAX_WORKERS), std::sync::atomic::Ordering::Relaxed);
        } else if failure > success && current > INITIAL_WORKERS {
            self.worker_count.store(std::cmp::max(current - 1, INITIAL_WORKERS), std::sync::atomic::Ordering::Relaxed);
        }
        
        // 重置计数器
        self.success_count.store(0, std::sync::atomic::Ordering::Relaxed);
        self.failure_count.store(0, std::sync::atomic::Ordering::Relaxed);
    }
}

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
/// 命令行参数
struct Args {
    /// Command to execute
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// 启动证明者
    Start {
        /// 节点ID
        #[arg(long, value_name = "NODE_ID")]
        node_id: Option<u64>,

        /// 在没有终端UI的情况下运行
        #[arg(long = "headless", action = ArgAction::SetTrue)]
        headless: bool,

        /// 用于证明的最大线程数。
        #[arg(long = "max-threads", value_name = "MAX_THREADS")]
        max_threads: Option<u32>,
    },
    /// 从节点列表文件启动多个证明者
    BatchFile {
        /// 节点列表文件路径(.txt)
        #[arg(long, value_name = "FILE_PATH")]
        file: String,

        /// 启动每个节点之间的延迟(秒)
        #[arg(long, default_value = "10")]
        start_delay: u64,

        /// 最大并发节点数
        #[arg(long, default_value = "50")]
        max_concurrent: usize,

        /// 启用详细错误日志记录
        #[arg(long)]
        verbose: bool,
    },
    /// 注册新用户
    RegisterUser {
        /// 用户的公共以太坊钱包地址。以'0x'开头的42字符十六进制字符串
        #[arg(long, value_name = "WALLET_ADDRESS")]
        wallet_address: String,
    },
    /// 向现有用户注册新节点，或将现有节点链接到用户。
    RegisterNode {
        /// 要注册的节点ID。如果未提供，将创建一个新节点。
        #[arg(long, value_name = "NODE_ID")]
        node_id: Option<u64>,
    },
    /// 清除节点配置并登出。
    Logout,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let nexus_environment_str = std::env::var("NEXUS_ENVIRONMENT").unwrap_or_default();
    let environment = nexus_environment_str
        .parse::<Environment>()
        .unwrap_or(Environment::default());

    let config_path = get_config_path()?;

    let args = Args::parse();
    match args.command {
        Command::Start {
            node_id,
            headless,
            max_threads,
        } => start(node_id, environment, config_path, headless, max_threads).await,
        Command::BatchFile {
            file,
            start_delay,
            max_concurrent,
            verbose,
        } => {
            if verbose {
            }
            start_batch_from_file_optimized(&file, Environment::default(), start_delay, max_concurrent, verbose).await
        },
        Command::Logout => {
            println!("Logging out and clearing node configuration file...");
            Config::clear_node_config(&config_path).map_err(Into::into)
        }
        Command::RegisterUser { wallet_address } => {
            println!("Registering user with wallet address: {}", wallet_address);
            let orchestrator = Box::new(OrchestratorClient::new(environment));
            register_user(&wallet_address, &config_path, orchestrator).await
        }
        Command::RegisterNode { node_id } => {
            let orchestrator = Box::new(OrchestratorClient::new(environment));
            register_node(node_id, &config_path, orchestrator).await
        }
    }
}

/// 启动Nexus CLI应用程序。
///
/// # 参数
/// * `node_id` - 此客户端的唯一标识符（如果可用）。
/// * `env` - 要连接的环境。
/// * `config_path` - 配置文件的路径。
/// * `headless` - 如果为true，则在没有终端UI的情况下运行。
/// * `max_threads` - 用于证明的可选最大线程数。
async fn start(
    node_id: Option<u64>,
    env: Environment,
    config_path: std::path::PathBuf,
    headless: bool,
    max_threads: Option<u32>,
) -> Result<(), Box<dyn Error>> {
    let mut node_id = node_id;
    // 如果未提供节点ID，尝试从配置文件加载。
    if node_id.is_none() && config_path.exists() {
        let config = Config::load_from_file(&config_path)?;
        node_id = Some(config.node_id.parse::<u64>().map_err(|e| {
            std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!(
                    "Failed to parse node_id {:?} from the config file as a u64: {}",
                    config.node_id, e
                ),
            )
        })?);
        println!("从配置文件读取节点ID: {}", node_id.unwrap());
    }

    // 为证明者创建签名密钥。
    let mut csprng = rand_core::OsRng;
    let signing_key: SigningKey = SigningKey::generate(&mut csprng);
    let orchestrator_client = OrchestratorClient::new(env);
    // 将工作线程数限制在[1,8]范围内。暂时保持较低以避免速率限制。
    let num_workers: usize = max_threads.unwrap_or(1).clamp(1, 8) as usize;
    let (shutdown_sender, _) = broadcast::channel(1); // 只需要一个关闭信号

    // 加载配置以获取用于分析的client_id
    let config_path = get_config_path()?;
    let client_id = if config_path.exists() {
        match Config::load_from_file(&config_path) {
            Ok(config) => {
                // 首先尝试user_id，然后是node_id，最后回退到UUID
                if !config.user_id.is_empty() {
                    config.user_id
                } else if !config.node_id.is_empty() {
                    config.node_id
                } else {
                    uuid::Uuid::new_v4().to_string() // 回退到随机UUID
                }
            }
            Err(_) => uuid::Uuid::new_v4().to_string(), // 回退到随机UUID
        }
    } else {
        uuid::Uuid::new_v4().to_string() // 回退到随机UUID
    };

    let (mut event_receiver, mut join_handles) = match node_id {
        Some(node_id) => {
            start_authenticated_workers(
                node_id,
                signing_key.clone(),
                orchestrator_client.clone(),
                num_workers,
                shutdown_sender.subscribe(),
                env,
                client_id,
            )
            .await
        }
        None => {
            start_anonymous_workers(num_workers, shutdown_sender.subscribe(), env, client_id).await
        }
    };

    if !headless {
        // 终端设置
        enable_raw_mode()?;
        let mut stdout = io::stdout();
        execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;

        // 使用Crossterm后端初始化终端。
        let backend = CrosstermBackend::new(stdout);
        let mut terminal = Terminal::new(backend)?;

        // 创建应用程序并运行。
        let app = ui::App::new(
            node_id,
            *orchestrator_client.environment(),
            event_receiver,
            shutdown_sender,
        );
        let res = ui::run(&mut terminal, app).await;

        // 运行应用程序后清理终端。
        disable_raw_mode()?;
        execute!(
            terminal.backend_mut(),
            LeaveAlternateScreen,
            DisableMouseCapture
        )?;
        terminal.show_cursor()?;

        res?;
    } else {
        // 无头模式：将事件记录到控制台。

        // 在Ctrl+C上触发关闭
        let shutdown_sender_clone = shutdown_sender.clone();
        tokio::spawn(async move {
            if tokio::signal::ctrl_c().await.is_ok() {
                let _ = shutdown_sender_clone.send(());
            }
        });

        let mut shutdown_receiver = shutdown_sender.subscribe();
        loop {
            tokio::select! {
                Some(event) = event_receiver.recv() => {
                    println!("{}", event);
                }
                _ = shutdown_receiver.recv() => {
                    break;
                }
            }
        }
    }
    println!("\nExiting...");
    for handle in join_handles.drain(..) {
        let _ = handle.await;
    }
    println!("Nexus CLI application exited successfully.");
    Ok(())
}

/// 监控任务，无限重试（无替换）
async fn monitor_infinite_retry(
    mut join_set: JoinSet<(u64, Result<(), Box<dyn Error + Send + Sync>>)>,
    display: Arc<FixedLineDisplay>,
) {
    tokio::pin! {
        let ctrl_c = tokio::signal::ctrl_c();
    }

    loop {
        tokio::select! {
            // 处理已完成的任务（在无限重试的情况下不应发生）
            Some(result) = join_set.join_next() => {
                if let Ok((node_id, prover_result)) = result {
                    match prover_result {
                        Ok(_) => {
                            println!("🎯 [Node-{}] Prover completed successfully (unexpected)", node_id);
                            display.update_node_status(node_id, "✅ Completed".to_string()).await;
                        },
                        Err(e) => {
                            println!("❌ [Node-{}] Prover exited unexpectedly: {}", node_id, e);
                            display.update_node_status(node_id, format!("❌ Unexpected exit: {}", e)).await;
                        }
                    }
                }
            }

            // 处理关闭信号
            _ = &mut ctrl_c => {
                println!("🛑 Shutdown signal received. Stopping all provers...");
                join_set.abort_all();
                break;
            }

            // 如果所有任务意外退出，则退出监控
            else => {
                println!("⚠️ All nodes have exited unexpectedly.");
                break;
            }
        }
    }

    println!("✅ All provers stopped.");
}

/// 优化的批量启动函数 - 集成内存监控和动态节点管理
async fn start_batch_from_file_optimized(
    file_path: &str,
    env: Environment,
    start_delay: u64,
    max_concurrent: usize,
    verbose: bool,
) -> Result<(), Box<dyn Error>> {
    // 加载节点列表
    let node_list = NodeList::load_from_file(file_path)?;
    let all_nodes = node_list.node_ids().to_vec();

    if all_nodes.is_empty() {
        return Err("Node list is empty".into());
    }

    println!("🚀 Starting optimized batch processing from file: {}", file_path);
    println!("📊 Total nodes: {}", all_nodes.len());
    println!("🔄 Max concurrent: {}", max_concurrent);
    println!("⏱️  Start delay: {}s", start_delay);
    println!("🌍 Environment: {:?}", env);
    println!("🧠 Memory-based auto-scaling enabled");
    println!("═══════════════════════════════════════");

    // 创建内存监控器
    let memory_monitor = Arc::new(memory_monitor::MemoryMonitor::new_default());
    
    // 启动内存监控
    memory_monitor.start_monitoring().await.map_err(|e| format!("Failed to start memory monitoring: {}", e))?;

    // 创建增强显示管理器
    let display = Arc::new(enhanced_display::EnhancedDisplay::new(
        memory_monitor.clone(),
        20, // 最大日志条目数
    ));

    // 创建动态节点管理器配置
    let manager_config = dynamic_node_manager::DynamicNodeManagerConfig {
        min_start_interval: 1, // 初始启动间隔固定为1秒，不受start_delay影响
        max_start_interval: start_delay * 3, // 最大启动间隔为原始延迟的3倍
        initial_nodes: std::cmp::min(2, max_concurrent), // 初始启动2个节点
        max_nodes: all_nodes.len(), // 最大节点数不超过实际可用节点数
    };

    // 创建动态节点管理器
    let node_manager = Arc::new(dynamic_node_manager::DynamicNodeManager::new(
        all_nodes.clone(),
        memory_monitor.clone(),
        Some(manager_config),
    ));

    // 启动动态节点管理器
    let display_clone = display.clone();
    let env_clone = env.clone();
    let verbose_clone = verbose;
    
    node_manager.start_manager(move |node_id, shutdown_sender| {
        let display = display_clone.clone();
        let env = env_clone.clone();
        let verbose = verbose_clone;
        
        async move {
            // println!("[DEBUG] Node task START for node_id={}", node_id);
            
            // 记录节点启动日志
            display.add_scaling_log(
                enhanced_display::ScalingOperation::NodeStarted,
                Some(node_id),
                "Node started by dynamic manager".to_string(),
            ).await;
            // println!("[DEBUG] Node {}: scaling log added", node_id);

            // 立即设置节点初始状态，确保显示界面能看到该节点
            // println!("[DEBUG] Node {}: about to set initial status", node_id);
            display.update_node_status(node_id, "🚀 Starting...".to_string()).await;
            // println!("[DEBUG] Node {}: initial status set", node_id);

            // 创建签名密钥
            let mut csprng = rand_core::OsRng;
            let signing_key: SigningKey = SigningKey::generate(&mut csprng);
            
            let orchestrator_client = OrchestratorClient::new(env);

            // 启动认证工作线程
            let (mut event_receiver, join_handles) = start_authenticated_workers(
                node_id,
                signing_key,
                orchestrator_client,
                1, // 每个节点单线程
                shutdown_sender.subscribe(),
                env,
                node_id.to_string(),
            ).await;
            // println!("[DEBUG] Node {}: authenticated workers started", node_id);
            
            // 立即发送一个初始状态事件，确保节点显示
            let _ = event_receiver.try_recv(); // 清空可能的事件
            display.update_node_status(node_id, "🔄 Workers started, waiting for tasks...".to_string()).await;

            // 处理事件
            let mut shutdown_receiver = shutdown_sender.subscribe();
            // println!("[DEBUG] Node {}: entering event loop", node_id);
            
            loop {
                tokio::select! {
                    Some(event) = event_receiver.recv() => {
                        let event_str = event.to_string();
                        // println!("[DEBUG] Node {}: received event: {}", node_id, event_str);
                        display.update_node_status(node_id, event_str.clone()).await;
                        
                        if verbose {
                            println!("[Node-{}] {}", node_id, event_str);
                        }
                    }
                    _ = shutdown_receiver.recv() => {
                        // 收到优雅关闭信号
                        display.add_scaling_log(
                            enhanced_display::ScalingOperation::NodeStopped,
                            Some(node_id),
                            "Graceful shutdown signal received".to_string(),
                        ).await;
                        // 新增：主动上报 "Stopped" 状态，触发 EnhancedDisplay 移除节点
                        display.update_node_status(node_id, "Stopped".to_string()).await;
                        break;
                    }
                }
            }

            // 等待所有工作线程完成
            // println!("[DEBUG] Node {}: waiting for worker threads to complete", node_id);
            for handle in join_handles {
                let _ = handle.await;
            }
            // println!("[DEBUG] Node {}: all worker threads completed", node_id);
        }
    }).await;

    // 等待一小段时间让初始节点启动
    tokio::time::sleep(std::time::Duration::from_secs(2)).await;

    println!("✅ Dynamic node manager started!");
    println!("🛑 Press Ctrl+C to gracefully stop all nodes");

    // 设置Ctrl+C信号处理
    let node_manager_clone = node_manager.clone();
    let display_clone = display.clone();
    
    tokio::spawn(async move {
        if tokio::signal::ctrl_c().await.is_ok() {
            println!("\n🛑 Ctrl+C received. Starting graceful shutdown...");
            
            // 记录优雅关闭日志
            display_clone.add_scaling_log(
                enhanced_display::ScalingOperation::EmergencyScaleDown,
                None,
                "Ctrl+C received, graceful shutdown initiated".to_string(),
            ).await;
            
            // 停止节点管理器
            node_manager_clone.stop_manager().await;
            
            // 优雅关闭所有节点
            node_manager_clone.graceful_shutdown_all().await;
            
            println!("✅ All nodes gracefully stopped.");
        }
    });

    // 主循环：监控和显示状态
    loop {
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        
        let active_count = node_manager.active_count().await;
        let pending_count = node_manager.pending_count().await;
        
        // 检查是否所有节点都已处理完毕
        if active_count == 0 && pending_count == 0 {
            println!("✅ All nodes have been processed.");
            break;
        }
        
        // 检查节点管理器是否还在运行
        if !node_manager.is_monitoring().await {
            println!("⚠️ Node manager has stopped.");
            break;
        }
    }

    // 停止内存监控
    memory_monitor.stop_monitoring();
    
    println!("🎉 Optimized batch processing completed successfully!");
    Ok(())
}
