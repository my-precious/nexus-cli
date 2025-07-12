//! Proof Statistics Persistence
//! 
//! Handles saving and loading proof statistics to/from disk to persist across restarts.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::fs;
use std::io;
use std::time::{SystemTime, UNIX_EPOCH};

/// 证明统计数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProofStats {
    /// 节点证明计数映射
    pub node_counts: HashMap<u64, u64>,
    /// 总证明数
    pub total_proofs: u64,
    /// 最后更新时间戳
    pub last_updated: u64,
    /// 会话开始时间戳
    pub session_start: u64,
    /// 会话ID（用于区分不同的运行会话）
    pub session_id: String,
}

impl ProofStats {
    /// 创建新的证明统计数据
    pub fn new() -> Self {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        
        Self {
            node_counts: HashMap::new(),
            total_proofs: 0,
            last_updated: now,
            session_start: now,
            session_id: Self::generate_session_id(),
        }
    }

    /// 生成会话ID
    fn generate_session_id() -> String {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};
        
        let mut hasher = DefaultHasher::new();
        SystemTime::now().hash(&mut hasher);
        format!("{:x}", hasher.finish())
    }

    /// 增加节点证明计数
    pub fn increment_proof_count(&mut self, node_id: u64) {
        let count = self.node_counts.entry(node_id).or_insert(0);
        *count += 1;
        self.total_proofs += 1;
        self.last_updated = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
    }

    /// 获取节点证明计数
    pub fn get_node_count(&self, node_id: u64) -> u64 {
        *self.node_counts.get(&node_id).unwrap_or(&0)
    }

    /// 获取总证明数
    pub fn get_total_proofs(&self) -> u64 {
        self.total_proofs
    }

    /// 获取所有节点计数
    pub fn get_all_node_counts(&self) -> &HashMap<u64, u64> {
        &self.node_counts
    }

    /// 合并另一个统计数据（用于重启后恢复）
    pub fn merge(&mut self, other: &ProofStats) {
        // 合并节点计数
        for (node_id, count) in &other.node_counts {
            let current_count = self.node_counts.entry(*node_id).or_insert(0);
            *current_count += count;
        }
        
        // 更新总计数
        self.total_proofs += other.total_proofs;
        
        // 更新最后更新时间
        if other.last_updated > self.last_updated {
            self.last_updated = other.last_updated;
        }
    }

    /// 重置统计数据（开始新会话）
    pub fn reset(&mut self) {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        
        self.node_counts.clear();
        self.total_proofs = 0;
        self.last_updated = now;
        self.session_start = now;
        self.session_id = Self::generate_session_id();
    }
}

impl Default for ProofStats {
    fn default() -> Self {
        Self::new()
    }
}

/// 证明统计管理器
pub struct ProofStatsManager {
    stats: ProofStats,
    file_path: PathBuf,
    auto_save_interval: u64, // 自动保存间隔（秒）
    last_save_time: u64,
}

impl ProofStatsManager {
    /// 创建新的统计管理器
    pub fn new(file_path: PathBuf) -> Self {
        Self {
            stats: ProofStats::new(),
            file_path,
            auto_save_interval: 30, // 每30秒自动保存一次
            last_save_time: 0,
        }
    }

    /// 从文件加载统计数据
    pub fn load_from_file(file_path: &Path) -> Result<Self, io::Error> {
        let stats = if file_path.exists() {
            let content = fs::read_to_string(file_path)?;
            serde_json::from_str(&content).unwrap_or_else(|_| ProofStats::new())
        } else {
            ProofStats::new()
        };

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        Ok(Self {
            stats,
            file_path: file_path.to_path_buf(),
            auto_save_interval: 30,
            last_save_time: now,
        })
    }

    /// 保存统计数据到文件
    pub fn save(&self) -> Result<(), io::Error> {
        // 确保目录存在
        if let Some(parent) = self.file_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let json = serde_json::to_string_pretty(&self.stats)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        
        fs::write(&self.file_path, json)?;
        Ok(())
    }

    /// 增加节点证明计数
    pub fn increment_proof_count(&mut self, node_id: u64) {
        self.stats.increment_proof_count(node_id);
        
        // 检查是否需要自动保存
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        
        if now - self.last_save_time >= self.auto_save_interval {
            if let Err(e) = self.save() {
                eprintln!("Failed to auto-save proof stats: {}", e);
            } else {
                self.last_save_time = now;
            }
        }
    }

    /// 获取节点证明计数
    pub fn get_node_count(&self, node_id: u64) -> u64 {
        self.stats.get_node_count(node_id)
    }

    /// 获取总证明数
    pub fn get_total_proofs(&self) -> u64 {
        self.stats.get_total_proofs()
    }

    /// 获取所有节点计数
    pub fn get_all_node_counts(&self) -> &HashMap<u64, u64> {
        self.stats.get_all_node_counts()
    }

    /// 重置统计数据
    pub fn reset(&mut self) -> Result<(), io::Error> {
        self.stats.reset();
        self.save()
    }

    /// 强制保存
    pub fn force_save(&mut self) -> Result<(), io::Error> {
        let result = self.save();
        if result.is_ok() {
            self.last_save_time = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs();
        }
        result
    }

    /// 获取统计文件路径
    pub fn get_file_path(&self) -> &Path {
        &self.file_path
    }

    /// 设置自动保存间隔
    pub fn set_auto_save_interval(&mut self, interval_seconds: u64) {
        self.auto_save_interval = interval_seconds;
    }
}

/// 获取证明统计文件路径
pub fn get_proof_stats_path() -> Result<PathBuf, io::Error> {
    let home_path = home::home_dir().ok_or(io::Error::new(
        io::ErrorKind::NotFound,
        "Home directory not found",
    ))?;
    let stats_path = home_path.join(".nexus").join("proof_stats.json");
    Ok(stats_path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_proof_stats_new() {
        let stats = ProofStats::new();
        assert_eq!(stats.total_proofs, 0);
        assert!(stats.node_counts.is_empty());
        assert!(!stats.session_id.is_empty());
    }

    #[test]
    fn test_increment_proof_count() {
        let mut stats = ProofStats::new();
        stats.increment_proof_count(123);
        stats.increment_proof_count(123);
        stats.increment_proof_count(456);
        
        assert_eq!(stats.get_node_count(123), 2);
        assert_eq!(stats.get_node_count(456), 1);
        assert_eq!(stats.get_total_proofs(), 3);
    }

    #[test]
    fn test_merge_stats() {
        let mut stats1 = ProofStats::new();
        stats1.increment_proof_count(123);
        stats1.increment_proof_count(456);
        
        let mut stats2 = ProofStats::new();
        stats2.increment_proof_count(123);
        stats2.increment_proof_count(789);
        
        stats1.merge(&stats2);
        
        assert_eq!(stats1.get_node_count(123), 2);
        assert_eq!(stats1.get_node_count(456), 1);
        assert_eq!(stats1.get_node_count(789), 1);
        assert_eq!(stats1.get_total_proofs(), 4);
    }

    #[test]
    fn test_save_and_load() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("test_stats.json");
        
        // 创建并保存统计数据
        let mut manager = ProofStatsManager::new(file_path.clone());
        manager.increment_proof_count(123);
        manager.increment_proof_count(456);
        manager.save().unwrap();
        
        // 加载统计数据
        let loaded_manager = ProofStatsManager::load_from_file(&file_path).unwrap();
        
        assert_eq!(loaded_manager.get_node_count(123), 1);
        assert_eq!(loaded_manager.get_node_count(456), 1);
        assert_eq!(loaded_manager.get_total_proofs(), 2);
    }

    #[test]
    fn test_reset() {
        let mut stats = ProofStats::new();
        stats.increment_proof_count(123);
        stats.increment_proof_count(456);
        
        assert_eq!(stats.get_total_proofs(), 2);
        
        stats.reset();
        
        assert_eq!(stats.get_total_proofs(), 0);
        assert!(stats.node_counts.is_empty());
    }
} 