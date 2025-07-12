// 版权所有 (c) 2024 Nexus。保留所有权利。

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use sysinfo::System;
use tokio::sync::RwLock;
use tokio::time::sleep;

/// 内存监控配置
#[derive(Debug, Clone)]
pub struct MemoryConfig {
    /// 安全内存使用率阈值 (0.0-1.0)
    pub safe_threshold: f64,
    /// 警告内存使用率阈值 (0.0-1.0)
    pub warning_threshold: f64,
    /// 危险内存使用率阈值 (0.0-1.0)
    pub danger_threshold: f64,
    /// 内存检查间隔（秒）
    pub check_interval: u64,
    /// 最小节点数
    pub min_nodes: usize,
    /// 最大节点数
    pub max_nodes: usize,
    /// 初始节点数
    pub initial_nodes: usize,
}

impl Default for MemoryConfig {
    fn default() -> Self {
        Self {
            safe_threshold: 0.8,    // 70% 以下为安全
            warning_threshold: 0.88, // 80% 以下为警告
            danger_threshold: 0.95,  // 90% 以下为危险
            check_interval: 10,      // 每5秒检查一次
            min_nodes: 10,
            max_nodes: 50,
            initial_nodes: 5,
        }
    }
}

/// 内存使用状态
#[derive(Debug, Clone, PartialEq)]
pub enum MemoryStatus {
    /// 安全状态 - 内存使用率低于安全阈值
    Safe,
    /// 警告状态 - 内存使用率在警告阈值范围内
    Warning,
    /// 危险状态 - 内存使用率在危险阈值范围内
    Danger,
    /// 紧急状态 - 内存使用率超过危险阈值
    Emergency,
}

impl std::fmt::Display for MemoryStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MemoryStatus::Safe => write!(f, "Safe"),
            MemoryStatus::Warning => write!(f, "Warning"),
            MemoryStatus::Danger => write!(f, "Danger"),
            MemoryStatus::Emergency => write!(f, "Emergency"),
        }
    }
}

/// 内存信息
#[derive(Debug, Clone)]
pub struct MemoryInfo {
    /// 总内存（字节）
    pub total_memory: u64,
    /// 已用内存（字节）
    pub used_memory: u64,
    /// 可用内存（字节）
    pub available_memory: u64,
    /// 内存使用率 (0.0-1.0)
    pub usage_ratio: f64,
    /// 内存状态
    pub status: MemoryStatus,
    /// 检查时间戳
    pub timestamp: Instant,
}

impl MemoryInfo {
    /// 创建新的内存信息实例
    pub fn new(total: u64, _used: u64, available: u64) -> Self {
        let used = if total > available { total - available } else { 0 };
        let usage_ratio = if total > 0 {
            used as f64 / total as f64
        } else {
            0.0
        };

        let status = if usage_ratio >= 0.95 {
            MemoryStatus::Emergency
        } else if usage_ratio >= 0.88 {
            MemoryStatus::Danger
        } else if usage_ratio >= 0.8 {
            MemoryStatus::Warning
        } else {
            MemoryStatus::Safe
        };

        Self {
            total_memory: total,
            used_memory: used,
            available_memory: available,
            usage_ratio,
            status,
            timestamp: Instant::now(),
        }
    }

    /// 格式化内存大小为人类可读格式
    pub fn format_memory_size(bytes: u64) -> String {
        const KB: f64 = 1024.0;
        const MB: f64 = KB * 1024.0;
        const GB: f64 = MB * 1024.0;

        if bytes >= GB as u64 {
            format!("{:.2} GB", bytes as f64 / GB)
        } else if bytes >= MB as u64 {
            format!("{:.2} MB", bytes as f64 / MB)
        } else if bytes >= KB as u64 {
            format!("{:.2} KB", bytes as f64 / KB)
        } else {
            format!("{} B", bytes)
        }
    }

    /// 获取内存使用率的百分比字符串
    pub fn usage_percentage(&self) -> String {
        format!("{:.1}%", self.usage_ratio * 100.0)
    }
}

/// 内存监控器
pub struct MemoryMonitor {
    /// 内存监控配置
    config: MemoryConfig,
    /// 系统信息实例
    system: Arc<RwLock<System>>,
    /// 当前内存信息
    current_memory: Arc<RwLock<Option<MemoryInfo>>>,
    /// 最后检查时间
    last_check: Arc<RwLock<Instant>>,
    /// 监控是否运行中
    is_running: Arc<AtomicU64>,
}

impl MemoryMonitor {
    /// 创建新的内存监控器
    pub fn new(config: MemoryConfig) -> Self {
        Self {
            system: Arc::new(RwLock::new(System::new())),
            current_memory: Arc::new(RwLock::new(None)),
            last_check: Arc::new(RwLock::new(Instant::now())),
            is_running: Arc::new(AtomicU64::new(0)),
            config,
        }
    }

    /// 使用默认配置创建内存监控器
    pub fn new_default() -> Self {
        Self::new(MemoryConfig::default())
    }

    /// 获取当前内存信息
    pub async fn get_memory_info(&self) -> Result<MemoryInfo, Box<dyn std::error::Error + Send + Sync>> {
        let mut system = self.system.write().await;
        system.refresh_memory();
        
        let total_memory = system.total_memory();
        let used_memory = system.used_memory();
        let available_memory = system.available_memory();
        
        let memory_info = MemoryInfo::new(total_memory, used_memory, available_memory);
        
        // 更新当前内存信息
        {
            let mut current = self.current_memory.write().await;
            *current = Some(memory_info.clone());
        }
        
        // 更新最后检查时间
        {
            let mut last_check = self.last_check.write().await;
            *last_check = Instant::now();
        }
        
        Ok(memory_info)
    }

    /// 获取当前内存状态
    pub async fn get_memory_status(&self) -> Result<MemoryStatus, Box<dyn std::error::Error + Send + Sync>> {
        let memory_info = self.get_memory_info().await?;
        Ok(memory_info.status)
    }

    /// 检查是否应该扩容（增加节点）
    pub async fn should_scale_up(&self) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
        let memory_info = self.get_memory_info().await?;
        Ok(memory_info.usage_ratio < self.config.safe_threshold)
    }

    /// 检查是否应该缩容（减少节点）
    pub async fn should_scale_down(&self) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
        let memory_info = self.get_memory_info().await?;
        Ok(memory_info.usage_ratio >= self.config.warning_threshold)
    }

    /// 检查是否应该紧急缩容
    pub async fn should_emergency_scale_down(&self) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
        let memory_info = self.get_memory_info().await?;
        Ok(memory_info.usage_ratio >= self.config.danger_threshold)
    }

    /// 根据内存状态建议的节点数量
    pub async fn get_suggested_node_count(&self, current_nodes: usize) -> Result<usize, Box<dyn std::error::Error + Send + Sync>> {
        let memory_info = self.get_memory_info().await?;
        
        let suggested = match memory_info.status {
            MemoryStatus::Safe => {
                // 安全状态：建议达到配置的最大节点数
                self.config.max_nodes
            }
            MemoryStatus::Warning => {
                // 警告状态：建议减少节点数
                std::cmp::max(current_nodes.saturating_sub(1), self.config.min_nodes)
            }
            MemoryStatus::Danger => {
                // 危险状态：减少节点
                std::cmp::max(current_nodes.saturating_sub(2), self.config.min_nodes)
            }
            MemoryStatus::Emergency => {
                // 紧急状态：大幅减少节点
                std::cmp::max(current_nodes.saturating_sub(3), self.config.min_nodes)
            }
        };
        
        Ok(suggested)
    }

    /// 启动持续监控
    pub async fn start_monitoring(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        if self.is_running.load(Ordering::Acquire) == 1 {
            return Ok(()); // 已经在运行
        }
        
        self.is_running.store(1, Ordering::Release);
        
        let config = self.config.clone();
        let system = self.system.clone();
        let current_memory = self.current_memory.clone();
        let last_check = self.last_check.clone();
        let is_running = self.is_running.clone();
        
        tokio::spawn(async move {
            while is_running.load(Ordering::Acquire) == 1 {
                // 更新系统信息
                {
                    let mut sys = system.write().await;
                    sys.refresh_memory();
                }
                
                // 获取内存信息
                let total_memory = {
                    let sys = system.read().await;
                    sys.total_memory()
                };
                let used_memory = {
                    let sys = system.read().await;
                    sys.used_memory()
                };
                let available_memory = {
                    let sys = system.read().await;
                    sys.available_memory()
                };
                
                let memory_info = MemoryInfo::new(total_memory, used_memory, available_memory);
                
                // 更新当前内存信息
                {
                    let mut current = current_memory.write().await;
                    *current = Some(memory_info);
                }
                
                // 更新最后检查时间
                {
                    let mut last = last_check.write().await;
                    *last = Instant::now();
                }
                
                // 等待下次检查
                sleep(Duration::from_secs(config.check_interval)).await;
            }
        });
        
        Ok(())
    }

    /// 停止监控
    pub fn stop_monitoring(&self) {
        self.is_running.store(0, Ordering::Release);
    }

    /// 检查监控是否正在运行
    pub fn is_monitoring(&self) -> bool {
        self.is_running.load(Ordering::Acquire) == 1
    }

    /// 获取配置
    pub fn config(&self) -> &MemoryConfig {
        &self.config
    }

    /// 更新配置
    pub fn update_config(&mut self, config: MemoryConfig) {
        self.config = config;
    }

    /// 获取最后检查时间
    pub async fn get_last_check_time(&self) -> Instant {
        *self.last_check.read().await
    }

    /// 获取当前内存信息（如果可用）
    pub async fn get_current_memory_info(&self) -> Option<MemoryInfo> {
        self.current_memory.read().await.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[tokio::test]
    async fn test_memory_config_default() {
        let config = MemoryConfig::default();
        assert_eq!(config.safe_threshold, 0.7);
        assert_eq!(config.warning_threshold, 0.8);
        assert_eq!(config.danger_threshold, 0.9);
        assert_eq!(config.check_interval, 1);
        assert_eq!(config.min_nodes, 1);
        assert_eq!(config.max_nodes, 50);
        assert_eq!(config.initial_nodes, 2);
    }

    #[tokio::test]
    async fn test_memory_info_creation() {
        let info = MemoryInfo::new(1000, 300, 700);
        assert_eq!(info.total_memory, 1000);
        assert_eq!(info.used_memory, 300);
        assert_eq!(info.available_memory, 700);
        assert_eq!(info.usage_ratio, 0.3);
        assert_eq!(info.status, MemoryStatus::Safe);
    }

    #[tokio::test]
    async fn test_memory_status_calculation() {
        // 测试安全状态
        let info = MemoryInfo::new(1000, 600, 400);
        assert_eq!(info.status, MemoryStatus::Safe);
        
        // 测试警告状态
        let info = MemoryInfo::new(1000, 750, 250);
        assert_eq!(info.status, MemoryStatus::Warning);
        
        // 测试危险状态
        let info = MemoryInfo::new(1000, 850, 150);
        assert_eq!(info.status, MemoryStatus::Danger);
        
        // 测试紧急状态
        let info = MemoryInfo::new(1000, 950, 50);
        assert_eq!(info.status, MemoryStatus::Emergency);
    }

    #[tokio::test]
    async fn test_memory_formatting() {
        assert_eq!(MemoryInfo::format_memory_size(1024), "1.00 KB");
        assert_eq!(MemoryInfo::format_memory_size(1024 * 1024), "1.00 MB");
        assert_eq!(MemoryInfo::format_memory_size(1024 * 1024 * 1024), "1.00 GB");
        assert_eq!(MemoryInfo::format_memory_size(512), "512 B");
    }

    #[tokio::test]
    async fn test_memory_monitor_creation() {
        let monitor = MemoryMonitor::new_default();
        assert!(!monitor.is_monitoring());
        assert_eq!(monitor.config().safe_threshold, 0.7);
    }

    #[tokio::test]
    async fn test_memory_monitor_basic_operations() {
        let monitor = MemoryMonitor::new_default();
        
        // 测试获取内存信息
        let memory_info = monitor.get_memory_info().await.unwrap();
        assert!(memory_info.total_memory > 0);
        assert!(memory_info.used_memory > 0);
        assert!(memory_info.usage_ratio > 0.0);
        assert!(memory_info.usage_ratio <= 1.0);
        
        // 测试获取内存状态
        let status = monitor.get_memory_status().await.unwrap();
        assert!(matches!(status, MemoryStatus::Safe | MemoryStatus::Warning | MemoryStatus::Danger | MemoryStatus::Emergency));
    }

    #[tokio::test]
    async fn test_scale_suggestions() {
        let mut config = MemoryConfig::default();
        config.min_nodes = 1;
        config.max_nodes = 10;
        
        let monitor = MemoryMonitor::new(config);
        
        // 模拟不同内存状态下的建议
        // 注意：这里我们无法直接模拟内存状态，但可以测试逻辑
        let suggested = monitor.get_suggested_node_count(5).await.unwrap();
        assert!(suggested >= 1 && suggested <= 10);
    }

    #[tokio::test]
    async fn test_monitoring_lifecycle() {
        let monitor = MemoryMonitor::new_default();
        
        // 初始状态
        assert!(!monitor.is_monitoring());
        
        // 启动监控
        monitor.start_monitoring().await.unwrap();
        assert!(monitor.is_monitoring());
        
        // 等待一小段时间让监控运行
        sleep(Duration::from_millis(100)).await;
        
        // 检查是否有内存信息
        let memory_info = monitor.get_current_memory_info().await;
        assert!(memory_info.is_some());
        
        // 停止监控
        monitor.stop_monitoring();
        assert!(!monitor.is_monitoring());
    }

    #[tokio::test]
    async fn test_config_update() {
        let mut monitor = MemoryMonitor::new_default();
        let original_threshold = monitor.config().safe_threshold;
        
        let mut new_config = MemoryConfig::default();
        new_config.safe_threshold = 0.6;
        monitor.update_config(new_config);
        
        assert_eq!(monitor.config().safe_threshold, 0.6);
        assert_ne!(monitor.config().safe_threshold, original_threshold);
    }

    #[tokio::test]
    async fn test_usage_percentage() {
        let info = MemoryInfo::new(1000, 750, 250);
        assert_eq!(info.usage_percentage(), "75.0%");
        
        let info = MemoryInfo::new(1000, 500, 500);
        assert_eq!(info.usage_percentage(), "50.0%");
    }

    #[tokio::test]
    async fn test_zero_memory_handling() {
        let info = MemoryInfo::new(0, 0, 0);
        assert_eq!(info.usage_ratio, 0.0);
        assert_eq!(info.status, MemoryStatus::Safe);
    }
} 