pub mod prover {
    // Queue sizes. Chosen to be larger than the tasks API page size (currently, 50)
    pub const TASK_QUEUE_SIZE: usize = 100;
    pub const EVENT_QUEUE_SIZE: usize = 100;
    pub const RESULT_QUEUE_SIZE: usize = 100;

    // Task fetching thresholds - 优化配置
    pub const BATCH_SIZE: usize = TASK_QUEUE_SIZE / 3; // 增加到33个任务 (原来是20)
    pub const LOW_WATER_MARK: usize = TASK_QUEUE_SIZE / 3; // 提高低水位标记到33 (原来是25)
    pub const MAX_404S_BEFORE_GIVING_UP: usize = 3; // 减少404容忍度 (原来是5)
    
    // 退避策略优化
    pub const BACKOFF_DURATION: u64 = 10000; // 减少到10秒 (原来是30秒)
    pub const MIN_BACKOFF_DURATION: u64 = 5000; // 最小退避5秒
    pub const MAX_BACKOFF_DURATION: u64 = 60000; // 最大退避60秒
    
    pub const QUEUE_LOG_INTERVAL: u64 = 30000; // 30 seconds

    /// How long a task ID remains in the duplicate-prevention cache before expiring.
    pub const CACHE_EXPIRATION: u64 = 300000; // 5 minutes
    
    // 健康检查配置
    pub const MAX_CONSECUTIVE_EMPTY_FETCHES: u32 = 5; // 最大连续空获取次数
    pub const FORCE_FETCH_TIMEOUT: u64 = 300000; // 强制获取超时时间 (5分钟)
}
