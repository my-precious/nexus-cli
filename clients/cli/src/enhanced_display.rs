// 版权所有 (c) 2024 Nexus。保留所有权利。

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{RwLock, Mutex};
use chrono::{DateTime, Local};
use crate::memory_monitor::{MemoryInfo, MemoryStatus, MemoryMonitor};
use regex::Regex;

/// 伸缩操作日志条目
#[derive(Debug, Clone)]
pub struct ScalingLogEntry {
    pub timestamp: DateTime<Local>,
    pub operation: ScalingOperation,
    pub node_id: Option<u64>,
    pub reason: String,
    pub memory_usage: f64,
}

/// 伸缩操作类型
#[derive(Debug, Clone)]
pub enum ScalingOperation {
    ScaleUp,
    ScaleDown,
    EmergencyScaleDown,
    NodeStarted,
    NodeStopped,
}

impl std::fmt::Display for ScalingOperation {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ScalingOperation::ScaleUp => write!(f, "🟢 扩容"),
            ScalingOperation::ScaleDown => write!(f, "🟡 缩容"),
            ScalingOperation::EmergencyScaleDown => write!(f, "🔴 紧急缩容"),
            ScalingOperation::NodeStarted => write!(f, "▶️  节点启动"),
            ScalingOperation::NodeStopped => write!(f, "⏹️  节点停止"),
        }
    }
}

/// 增强的显示管理器
#[derive(Clone)]
pub struct EnhancedDisplay {
    /// 节点状态信息
    node_lines: Arc<RwLock<HashMap<u64, String>>>,
    /// 节点证明计数
    proof_counts: Arc<RwLock<HashMap<u64, u64>>>,
    /// 总证明数
    total_proofs: Arc<RwLock<u64>>,
    /// 伸缩操作日志
    scaling_logs: Arc<RwLock<Vec<ScalingLogEntry>>>,
    /// 内存监控器
    memory_monitor: Arc<MemoryMonitor>,
    /// 最后渲染哈希
    last_render_hash: Arc<Mutex<u64>>,
    /// 启动时间
    start_time: DateTime<Local>,
    /// 最大日志条目数
    max_log_entries: usize,
}

impl EnhancedDisplay {
    /// 创建新的增强显示管理器
    pub fn new(memory_monitor: Arc<MemoryMonitor>, max_log_entries: usize) -> Self {
        Self {
            node_lines: Arc::new(RwLock::new(HashMap::new())),
            proof_counts: Arc::new(RwLock::new(HashMap::new())),
            total_proofs: Arc::new(RwLock::new(0)),
            scaling_logs: Arc::new(RwLock::new(Vec::new())),
            memory_monitor,
            last_render_hash: Arc::new(Mutex::new(0)),
            start_time: Local::now(),
            max_log_entries,
        }
    }

    /// 更新节点状态
    pub async fn update_node_status(&self, node_id: u64, status: String) {
        // 检查是否是提交成功的状态
        if status.contains("Proof submitted") || status.contains("Successfully submitted proof") {
            self.increment_proof_count(node_id).await;
        }
        
        // 新增：如果状态包含 "Stopped" 或 "Shutdown"，则移除该节点
        if status.contains("Stopped") || status.contains("Shutdown") {
            let mut lines = self.node_lines.write().await;
            if lines.remove(&node_id).is_some() {
                // 触发重新渲染
                let display = self.clone();
                tokio::spawn(async move {
                    display.render_display_optimized().await;
                });
            }
            return;
        }
        // println!("[DEBUG] update_node_status called: node_id={}, status={}", node_id, status);

        let needs_update = {
            let lines = self.node_lines.read().await;
            lines.get(&node_id) != Some(&status)
        };

        if needs_update {
            {
                let mut lines = self.node_lines.write().await;
                lines.insert(node_id, status.clone());
            }
            
            // 使用 spawn 来避免阻塞调用线程
            let display = self.clone();
            tokio::spawn(async move {
                display.render_display_optimized().await;
            });
        }
    }

    /// 增加证明计数
    async fn increment_proof_count(&self, node_id: u64) {
        let mut counts = self.proof_counts.write().await;
        let count = counts.entry(node_id).or_insert(0);
        *count += 1;

        let mut total = self.total_proofs.write().await;
        *total += 1;
    }

    /// 添加伸缩操作日志
    pub async fn add_scaling_log(&self, operation: ScalingOperation, node_id: Option<u64>, reason: String) {
        let memory_info = self.memory_monitor.get_memory_info().await.unwrap_or_else(|_| {
            // 如果获取内存信息失败，使用默认值
            crate::memory_monitor::MemoryInfo::new(0, 0, 0)
        });

        let log_entry = ScalingLogEntry {
            timestamp: Local::now(),
            operation,
            node_id,
            reason,
            memory_usage: memory_info.usage_ratio,
        };

        {
            let mut logs = self.scaling_logs.write().await;
            logs.push(log_entry);
            
            // 保持日志条目数量在限制内
            if logs.len() > self.max_log_entries {
                logs.remove(0);
            }
        }

        // 触发重新渲染
        self.render_display_optimized().await;
    }

    /// 优化渲染（避免重复渲染）
    async fn render_display_optimized(&self) {
        // 先获取所有需要的数据，避免锁的嵌套
        let (lines, logs, current_hash) = {
            let lines = self.node_lines.read().await;
            let logs = self.scaling_logs.read().await;

            let mut hasher = std::collections::hash_map::DefaultHasher::new();
            for (id, status) in lines.iter() {
                std::hash::Hasher::write_u64(&mut hasher, *id);
                std::hash::Hasher::write(&mut hasher, status.as_bytes());
            }
            for log in logs.iter() {
                std::hash::Hasher::write(&mut hasher, format!("{:?}", log.operation).as_bytes());
                std::hash::Hasher::write_u64(&mut hasher, log.timestamp.timestamp() as u64);
            }
            let current_hash = std::hash::Hasher::finish(&mut hasher);
            
            // 克隆数据以避免长时间持有锁
            (lines.clone(), logs.clone(), current_hash)
        };

        // 检查是否需要重新渲染
        let should_render = {
            let mut last_hash = self.last_render_hash.lock().await;
            if *last_hash != current_hash {
                *last_hash = current_hash;
                true
            } else {
                false
            }
        };

        // 如果需要重新渲染，执行渲染
        if should_render {
            self.render_display(&lines, &logs).await;
        }
    }

    /// 渲染显示
    async fn render_display(&self, lines: &HashMap<u64, String>, logs: &[ScalingLogEntry]) {
        // 清屏并移动到顶部
        print!("\x1b[2J\x1b[H");

        let start_time_str = self.start_time.format("%Y-%m-%d %H:%M:%S").to_string();

        // 标题
        println!("🚀 Nexus Dynamic Mining Monitor - {}", start_time_str);
        println!("═══════════════════════════════════════");

        // 内存状态
        self.render_memory_status().await;

        // 节点统计
        self.render_node_statistics(lines).await;

        // 节点状态列表
        self.render_node_list(lines).await;

        // 伸缩操作日志
        self.render_scaling_logs(logs);

        // 操作提示
        println!("───────────────────────────────────────");
        println!("💡 Press Ctrl+C to stop all miners");
        println!("📊 Memory-based auto-scaling enabled");

        // 强制输出刷新
        use std::io::Write;
        std::io::stdout().flush().unwrap();
    }

    /// 渲染内存状态
    async fn render_memory_status(&self) {
        match self.memory_monitor.get_memory_info().await {
            Ok(memory_info) => {
                let status_icon = match memory_info.status {
                    MemoryStatus::Safe => "🟢",
                    MemoryStatus::Warning => "🟡",
                    MemoryStatus::Danger => "🟠",
                    MemoryStatus::Emergency => "🔴",
                };

                // 获取内存建议的节点数
                let active_count = self.node_lines.read().await.len();
                let suggested_nodes = match self.memory_monitor.get_suggested_node_count(active_count).await {
                    Ok(suggested) => suggested,
                    Err(_) => active_count,
                };

                // 紧凑的内存状态显示
                println!("💾 Memory: {} {} | Total: {} | Used: {} | Available: {} | 🧠 Suggested: {} nodes", 
                    status_icon,
                    memory_info.usage_percentage(),
                    MemoryInfo::format_memory_size(memory_info.total_memory),
                    MemoryInfo::format_memory_size(memory_info.used_memory),
                    MemoryInfo::format_memory_size(memory_info.available_memory),
                    suggested_nodes
                );
            }
            Err(_) => {
                println!("💾 Memory Status: ❓ Unable to get memory info");
            }
        }
    }

    /// 渲染节点统计
    async fn render_node_statistics(&self, lines: &HashMap<u64, String>) {
        let active_count = lines.len();
        let total_proofs = *self.total_proofs.read().await;
        
        // 紧凑的节点统计显示
        println!("📊 Nodes: {} Active | {} Success | {} Failed | 🎯 Proofs: {}", 
                 active_count, 0, 0, total_proofs);
        println!("───────────────────────────────────────");
    }

    /// 渲染节点列表
    async fn render_node_list(&self, lines: &HashMap<u64, String>) {
        use chrono::NaiveDateTime;
        if lines.is_empty() {
            println!("🖥️  Active Nodes:");
            println!("   No active nodes");
            println!("───────────────────────────────────────");
            return;
        }

        println!("🖥️  Active Nodes:");
        // 用正则提取 [YYYY-MM-DD HH:MM:SS] 时间戳
        let re = Regex::new(r"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]").unwrap();
        let mut node_statuses: Vec<(u64, String, Option<NaiveDateTime>)> = lines.iter().map(|(id, status)| {
            let time = re.captures(status)
                .and_then(|cap| cap.get(1))
                .and_then(|m| NaiveDateTime::parse_from_str(m.as_str(), "%Y-%m-%d %H:%M:%S").ok());
            (*id, status.clone(), time)
        }).collect();

        // 按时间降序排序（无时间的排最后）
        node_statuses.sort_by(|a, b| b.2.cmp(&a.2));

        // 只保留最近20条
        for (node_id, status, _) in node_statuses.iter().take(20) {
            let proof_count = *self.proof_counts.read().await.get(node_id).unwrap_or(&0);
            println!("   Node-{} (Proofs: {}): {}", node_id, proof_count, status);
        }
        println!("───────────────────────────────────────");
    }

    /// 渲染伸缩操作日志
    fn render_scaling_logs(&self, logs: &[ScalingLogEntry]) {
        println!("📝 Scaling Operations (Last {}):", self.max_log_entries);
        
        if logs.is_empty() {
            println!("   No scaling operations yet");
        } else {
            // 显示最近的日志条目（倒序）
            for log in logs.iter().rev().take(5) {
                let time_str = log.timestamp.format("%H:%M:%S").to_string();
                let node_info = log.node_id.map(|id| format!("Node-{}", id)).unwrap_or_else(|| "N/A".to_string());
                println!("   [{}] {} {} - {} (Memory: {:.1}%)", 
                    time_str, 
                    log.operation, 
                    node_info,
                    log.reason,
                    log.memory_usage * 100.0
                );
            }
        }
    }

    /// 获取当前活跃节点数
    pub async fn active_node_count(&self) -> usize {
        self.node_lines.read().await.len()
    }

    /// 获取总证明数
    pub async fn total_proof_count(&self) -> u64 {
        *self.total_proofs.read().await
    }

    /// 获取伸缩日志数量
    pub async fn scaling_log_count(&self) -> usize {
        self.scaling_logs.read().await.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::memory_monitor::MemoryMonitor;

    #[tokio::test]
    async fn test_enhanced_display_creation() {
        let memory_monitor = Arc::new(MemoryMonitor::new_default());
        let display = EnhancedDisplay::new(memory_monitor, 10);
        
        assert_eq!(display.active_node_count().await, 0);
        assert_eq!(display.total_proof_count().await, 0);
        assert_eq!(display.scaling_log_count().await, 0);
    }

    #[tokio::test]
    async fn test_node_status_update() {
        let memory_monitor = Arc::new(MemoryMonitor::new_default());
        let display = EnhancedDisplay::new(memory_monitor, 10);
        
        display.update_node_status(1, "🔄 Running".to_string()).await;
        assert_eq!(display.active_node_count().await, 1);
        
        display.update_node_status(1, "✅ Completed".to_string()).await;
        assert_eq!(display.active_node_count().await, 1);
    }

    #[tokio::test]
    async fn test_scaling_logs() {
        let memory_monitor = Arc::new(MemoryMonitor::new_default());
        let display = EnhancedDisplay::new(memory_monitor, 3);
        
        display.add_scaling_log(
            ScalingOperation::ScaleUp,
            Some(1),
            "Memory usage low".to_string()
        ).await;
        
        assert_eq!(display.scaling_log_count().await, 1);
        
        // 测试日志数量限制
        for i in 2..=5 {
            display.add_scaling_log(
                ScalingOperation::ScaleDown,
                Some(i),
                "Memory pressure".to_string()
            ).await;
        }
        
        assert_eq!(display.scaling_log_count().await, 3); // 应该被限制在3个
    }

    #[tokio::test]
    async fn test_proof_counting() {
        let memory_monitor = Arc::new(MemoryMonitor::new_default());
        let display = EnhancedDisplay::new(memory_monitor, 10);
        
        // 更新包含证明提交的状态
        display.update_node_status(1, "Proof submitted successfully".to_string()).await;
        assert_eq!(display.total_proof_count().await, 1);
        
        display.update_node_status(1, "Successfully submitted proof".to_string()).await;
        assert_eq!(display.total_proof_count().await, 2);
    }
} 