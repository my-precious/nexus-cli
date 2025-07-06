// 版权所有 (c) 2024 Nexus。保留所有权利。

use std::collections::{HashSet, VecDeque};
use std::sync::Arc;
use tokio::sync::{RwLock, broadcast};
use tokio::task::JoinSet;
use tokio::time::{sleep, Duration};

use crate::memory_monitor::MemoryMonitor;

/// 节点任务句柄及优雅停止信号
pub struct NodeHandle {
    pub node_id: u64,
    pub shutdown_sender: broadcast::Sender<()>,
}

/// 动态节点管理器配置
#[derive(Debug, Clone)]
pub struct DynamicNodeManagerConfig {
    pub min_start_interval: u64, // 最小启动间隔（秒）
    pub max_start_interval: u64, // 最大启动间隔（秒）
    pub initial_nodes: usize,    // 初始启动节点数
    pub max_nodes: usize,         // 最大节点数
}

impl Default for DynamicNodeManagerConfig {
    fn default() -> Self {
        Self {
            min_start_interval: 2,
            max_start_interval: 10,
            initial_nodes: 2,
            max_nodes: usize::MAX,
        }
    }
}

/// 动态节点管理器
pub struct DynamicNodeManager {
    /// 当前活跃节点ID集合
    active_nodes: Arc<RwLock<HashSet<u64>>>,
    /// 待启动节点队列
    pending_nodes: Arc<RwLock<VecDeque<u64>>>,
    /// 节点任务句柄池
    node_handles: Arc<RwLock<Vec<NodeHandle>>>,
    /// 节点JoinSet
    join_set: Arc<RwLock<JoinSet<u64>>>,
    /// 内存监控器
    memory_monitor: Arc<MemoryMonitor>,
    /// 管理循环是否运行
    is_running: Arc<RwLock<bool>>,
    /// 启动控制配置
    config: DynamicNodeManagerConfig,
    /// 总节点数
    total_nodes: usize,
}

impl DynamicNodeManager {
    /// 创建新的动态节点管理器
    pub fn new(
        all_node_ids: Vec<u64>,
        memory_monitor: Arc<MemoryMonitor>,
        config: Option<DynamicNodeManagerConfig>,
    ) -> Self {
        let total_nodes = all_node_ids.len();
        
        // 记录总节点数用于调试
        println!("🔧 Total available nodes: {}, memory monitor max_nodes: {}", 
                 total_nodes, memory_monitor.config().max_nodes);
        
        Self {
            active_nodes: Arc::new(RwLock::new(HashSet::new())),
            pending_nodes: Arc::new(RwLock::new(VecDeque::from(all_node_ids))),
            node_handles: Arc::new(RwLock::new(Vec::new())),
            join_set: Arc::new(RwLock::new(JoinSet::new())),
            memory_monitor,
            is_running: Arc::new(RwLock::new(false)),
            config: config.unwrap_or_default(),
            total_nodes,
        }
    }

    /// 启动动态管理循环（智能启动控制）
    pub async fn start_manager<F, Fut>(&self, spawn_node_fn: F)
    where
        F: Fn(u64, broadcast::Sender<()>) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = ()> + Send + 'static,
    {
        let is_running = self.is_running.clone();
        {
            let mut running = is_running.write().await;
            *running = true;
        }
        let active_nodes = self.active_nodes.clone();
        let pending_nodes = self.pending_nodes.clone();
        let node_handles = self.node_handles.clone();
        let join_set = self.join_set.clone();
        let memory_monitor = self.memory_monitor.clone();
        let spawn_node_fn = Arc::new(spawn_node_fn);
        let config = self.config.clone();
        let total_nodes = self.total_nodes;

        tokio::spawn(async move {
            println!("🚀 Dynamic node manager starting with config: initial_nodes={}, min_interval={}s, max_interval={}s", 
                     config.initial_nodes, config.min_start_interval, config.max_start_interval);
            
            // 检查初始化的节点数量
            let initial_pending_count = pending_nodes.read().await.len();
            println!("🔍 DEBUG: Initial pending nodes count: {}", initial_pending_count);
            
            // 1. 初始渐进式启动
            let mut initial_started = 0;
            while initial_started < config.initial_nodes {
                if !*is_running.read().await {
                    break;
                }
                let mut pending = pending_nodes.write().await;
                if let Some(node_id) = pending.pop_front() {
                    println!("🎯 Starting initial node {} ({}/{})", node_id, initial_started + 1, config.initial_nodes);
                    let (shutdown_sender, _shutdown_receiver) = broadcast::channel(1);
                    {
                        let mut active = active_nodes.write().await;
                        active.insert(node_id);
                    }
                    {
                        let mut handles = node_handles.write().await;
                        handles.push(NodeHandle { node_id, shutdown_sender: shutdown_sender.clone() });
                    }
                    let mut join_set = join_set.write().await;
                    let spawn_node_fn = spawn_node_fn.clone();
                    join_set.spawn(async move {
                        println!("[DEBUG] async task START for node_id={}", node_id);
                        println!("[DEBUG] Node {}: about to call spawn_node_fn", node_id);
                        
                        // 执行节点任务
                        spawn_node_fn(node_id, shutdown_sender.clone()).await;
                        
                        println!("[DEBUG] async task END for node_id={}", node_id);
                        node_id
                    });
                    initial_started += 1;
                } else {
                    println!("⚠️ No more pending nodes available for initial startup");
                    break;
                }
                sleep(Duration::from_secs(config.min_start_interval)).await;
            }

            println!("✅ Initial startup completed. Active nodes: {}", active_nodes.read().await.len());

            // 等待一小段时间让初始节点稳定
            sleep(Duration::from_secs(1)).await;

            // 2. 智能扩缩容循环
            loop {
                if !*is_running.read().await {
                    println!("🛑 Manager loop stopped");
                    break;
                }
                
                let current_count = active_nodes.read().await.len();
                let pending_count = pending_nodes.read().await.len();
                
                // 获取内存建议，但限制在总节点数范围内
                let suggested = match memory_monitor.get_suggested_node_count(current_count).await {
                    Ok(s) => std::cmp::min(s, total_nodes),
                    Err(e) => {
                        println!("❌ Failed to get suggested node count: {}", e);
                        current_count
                    }
                };

                // 获取内存信息用于调试
                let mem_info = match memory_monitor.get_memory_info().await {
                    Ok(info) => info,
                    Err(e) => {
                        println!("❌ Failed to get memory info: {}", e);
                        continue;
                    }
                };

                // 动态调整启动间隔
                let usage = mem_info.usage_ratio;
                let interval = if usage < memory_monitor.config().safe_threshold {
                    config.min_start_interval
                } else if usage < memory_monitor.config().warning_threshold {
                    (config.min_start_interval + config.max_start_interval) / 2
                } else {
                    config.max_start_interval
                };

                // 计算实际可达到的最大节点数（当前活跃 + 待启动）
                let max_achievable = current_count + pending_count;
                
                // 限制建议的节点数不超过实际可达到的最大值
                let adjusted_suggested = std::cmp::min(suggested, max_achievable);

                println!("📊 Scaling check: current={}, suggested={}, adjusted={}, pending={}, memory={:.1}%, interval={}s", 
                         current_count, suggested, adjusted_suggested, pending_count, usage * 100.0, interval);

                if adjusted_suggested > current_count && pending_count > 0 {
                    // 扩容 - 只有当调整后的建议数大于当前活跃数且有待启动节点时才扩容
                    let nodes_to_add = std::cmp::min(adjusted_suggested - current_count, pending_count);
                    println!("🔄 Scaling UP: {} -> {} (+{} nodes, memory: {:.1}%) - PENDING NODES: {}", 
                             current_count, current_count + nodes_to_add, nodes_to_add, usage * 100.0, pending_count);
                    let mut pending = pending_nodes.write().await;
                    if let Some(node_id) = pending.pop_front() {
                        println!("[DEBUG] spawn_node_fn will be called for node_id={}", node_id);
                        let (shutdown_sender, _shutdown_receiver) = broadcast::channel(1);
                        {
                            let mut active = active_nodes.write().await;
                            active.insert(node_id);
                        }
                        {
                            let mut handles = node_handles.write().await;
                            handles.push(NodeHandle { node_id, shutdown_sender: shutdown_sender.clone() });
                        }
                        let mut join_set = join_set.write().await;
                        let spawn_node_fn = spawn_node_fn.clone();
                        join_set.spawn(async move {
                            println!("[DEBUG] async task START for node_id={}", node_id);
                            println!("[DEBUG] Node {}: about to call spawn_node_fn", node_id);
                            
                            // 执行节点任务
                            spawn_node_fn(node_id, shutdown_sender.clone()).await;
                            
                            println!("[DEBUG] async task END for node_id={}", node_id);
                            node_id
                        });
                        // 智能启动间隔
                        println!("⏱️ Waiting {}s before next scale-up", interval);
                        sleep(Duration::from_secs(interval)).await;
                    }
                } else if adjusted_suggested < current_count {
                    // 缩容
                    println!("📉 Scaling DOWN: {} -> {} (memory: {:.1}%)", current_count, adjusted_suggested, usage * 100.0);
                    let mut handles = node_handles.write().await;
                    if let Some(handle) = handles.pop() {
                        println!("🛑 Stopping node {} for scale-down", handle.node_id);
                        let _ = handle.shutdown_sender.send(());
                        {
                            let mut active = active_nodes.write().await;
                            active.remove(&handle.node_id);
                        }
                        let mut pending = pending_nodes.write().await;
                        pending.push_back(handle.node_id);
                    }
                } else if adjusted_suggested == current_count + pending_count && pending_count > 0 {
                    println!("⚠️ Cannot scale up further: suggested={}, current={}, pending={}, max_achievable={}", suggested, current_count, pending_count, current_count + pending_count);
                } else if pending_count == 0 && adjusted_suggested > current_count {
                    println!("⚠️ Cannot scale up: suggested={}, current={}, but no pending nodes available", adjusted_suggested, current_count);
                } else if pending_count == 0 {
                    println!("✅ All nodes are active, no pending nodes to scale");
                } else {
                    println!("⏸️ No scaling needed: current={}, adjusted_suggested={}, pending={}", current_count, adjusted_suggested, pending_count);
                }
                
                // 添加详细的调试信息
                println!("🔍 DEBUG: adjusted_suggested > current_count = {}, pending_count > 0 = {}", 
                         adjusted_suggested > current_count, pending_count > 0);
                println!("🔍 DEBUG: suggested = {}, adjusted_suggested = {}, current_count = {}, pending_count = {}", 
                         suggested, adjusted_suggested, current_count, pending_count);
                
                // 检查周期
                let check_interval = memory_monitor.config().check_interval;
                println!("⏰ Next scaling check in {}s", check_interval);
                sleep(Duration::from_secs(check_interval)).await;
            }
        });
    }

    /// 停止管理循环
    pub async fn stop_manager(&self) {
        let mut running = self.is_running.write().await;
        *running = false;
    }

    /// 获取当前活跃节点数
    pub async fn active_count(&self) -> usize {
        self.active_nodes.read().await.len()
    }

    /// 获取待启动节点数
    pub async fn pending_count(&self) -> usize {
        self.pending_nodes.read().await.len()
    }

    /// 获取总节点数（活跃 + 待启动）
    pub async fn total_count(&self) -> usize {
        self.active_nodes.read().await.len() + self.pending_nodes.read().await.len()
    }

    /// 获取所有活跃节点ID
    pub async fn active_node_ids(&self) -> Vec<u64> {
        self.active_nodes.read().await.iter().copied().collect()
    }

    /// 检查节点管理器是否正在运行
    pub async fn is_monitoring(&self) -> bool {
        *self.is_running.read().await
    }

    /// 优雅关闭所有节点并等待其退出
    pub async fn graceful_shutdown_all(&self) {
        // 1. 发送优雅关闭信号
        {
            let handles = self.node_handles.read().await;
            for handle in handles.iter() {
                let _ = handle.shutdown_sender.send(());
            }
        }
        // 2. 清空活跃节点池
        {
            let mut active = self.active_nodes.write().await;
            active.clear();
        }
        // 3. 等待所有 JoinSet 任务完成
        let mut join_set = self.join_set.write().await;
        while let Some(_res) = join_set.join_next().await {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::memory_monitor::{MemoryMonitor};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tokio::sync::Mutex;

    #[tokio::test]
    async fn test_dynamic_node_manager_basic() {
        let memory_monitor = Arc::new(MemoryMonitor::new_default());
        let all_nodes = vec![1, 2, 3];
        let config = DynamicNodeManagerConfig {
            min_start_interval: 1,
            max_start_interval: 2,
            initial_nodes: 2,
            max_nodes: usize::MAX,
        };
        let manager = DynamicNodeManager::new(all_nodes.clone(), memory_monitor.clone(), Some(config));
        let started = Arc::new(AtomicUsize::new(0));
        let stopped = Arc::new(AtomicUsize::new(0));
        let stop_flag = Arc::new(Mutex::new(false));

        // 模拟节点任务
        let started2 = started.clone();
        let stopped2 = stopped.clone();
        let stop_flag2 = stop_flag.clone();
        manager.start_manager(move |_, shutdown| {
            let started2 = started2.clone();
            let stopped2 = stopped2.clone();
            let stop_flag2 = stop_flag2.clone();
            async move {
                started2.fetch_add(1, Ordering::SeqCst);
                // 等待优雅停止信号
                let _ = shutdown.subscribe().recv().await;
                stopped2.fetch_add(1, Ordering::SeqCst);
                // 标记已停止
                let mut flag = stop_flag2.lock().await;
                *flag = true;
            }
        }).await;

        // 等待一小段时间让节点启动
        sleep(Duration::from_millis(100)).await;
        assert!(manager.active_count().await > 0);
        // 停止管理器
        manager.stop_manager().await;
        // 主动优雅停止所有节点
        {
            let handles = manager.node_handles.read().await;
            for handle in handles.iter() {
                let _ = handle.shutdown_sender.send(());
            }
        }
        // 等待节点优雅停止
        sleep(Duration::from_millis(100)).await;
        // 检查优雅停止回调是否被调用
        let flag = stop_flag.lock().await;
        assert!(*flag);
    }

    #[tokio::test]
    async fn test_dynamic_node_manager_graceful_shutdown() {
        let memory_monitor = Arc::new(MemoryMonitor::new_default());
        let all_nodes = vec![1, 2, 3];
        let config = DynamicNodeManagerConfig {
            min_start_interval: 1,
            max_start_interval: 2,
            initial_nodes: 2,
            max_nodes: usize::MAX,
        };
        let manager = DynamicNodeManager::new(all_nodes.clone(), memory_monitor.clone(), Some(config));
        let started = Arc::new(AtomicUsize::new(0));
        let stopped = Arc::new(AtomicUsize::new(0));
        let stop_flag = Arc::new(Mutex::new(0));

        // 模拟节点任务
        let started2 = started.clone();
        let stopped2 = stopped.clone();
        let stop_flag2 = stop_flag.clone();
        manager.start_manager(move |_, shutdown| {
            let started2 = started2.clone();
            let stopped2 = stopped2.clone();
            let stop_flag2 = stop_flag2.clone();
            async move {
                started2.fetch_add(1, Ordering::SeqCst);
                // 等待优雅停止信号
                let _ = shutdown.subscribe().recv().await;
                stopped2.fetch_add(1, Ordering::SeqCst);
                // 标记已停止
                let mut flag = stop_flag2.lock().await;
                *flag += 1;
            }
        }).await;

        // 等待节点启动
        sleep(Duration::from_millis(100)).await;
        assert!(manager.active_count().await > 0);
        // 优雅关闭所有节点
        manager.graceful_shutdown_all().await;
        // 检查所有节点都已优雅退出
        let flag = stop_flag.lock().await;
        assert!(*flag > 0);
    }
} 