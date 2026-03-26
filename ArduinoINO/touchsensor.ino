/*
 * ============================================================================================
 * Arduino Mega 神经行为实验系统 (v6.10 生理学双锁高精版)
 * 硬件基础：TTP224 电容式数字触摸模块 + D7 LED 同步闪烁
 * 核心算法：【上升沿检测 (Edge Detection)】 + 【CPG 生理极限不应期 (Biological Refractory)】
 * 科学依据：小鼠最高舔舐频率 12Hz (间隔 83.3ms)，设定 85ms 强制冷却彻底消除高频电容抖动
 * ============================================================================================
 */

// --- [模块1：硬件物理引脚配置] ---
const int TOUCH_1_PIN = A1;    // 输入：1号水嘴 TTP224 模块 OUT1
const int VALVE_1_PIN = 30;    // 输出：1号水嘴电磁阀
const int TOUCH_2_PIN = A8;    // 输入：2号水嘴 TTP224 模块 OUT2
const int VALVE_2_PIN = 22;    // 输出：2号水嘴电磁阀
const int TRIGGER_PIN = 40;    // 输出：电生理 TTL 同步信号  (D44：TDT发送周期性同步信号（ADC8）到Arduino-LED)
const int VALVE_DROP_PIN = 4;  // 输出：独立维护给水阀
const int PAUSE_BUTTON_PIN = 3;// 输入：硬件暂停按钮
const int LED_PIN = 7;         // 输出：每次舔舐同步闪烁的 LED 指示灯
const int TDT_SYNC_PIN = 44;   // ← 新增：接收 TDT C0 TTL 同步信号

// --- [模块2：Nature 协议核心参数] ---
const int MAX_TOTAL_REWARDS = 150;     // Session 奖励发放上限
const unsigned long ITI_MS = 8000;     // 8s 试次间歇 (Inter-Trial Interval)
const int VALVE_ON_MS = 200;           // 奖励给水时长
const int STABILIZE_MS = 200;          // 奖励发放后的屏蔽期，防止机械干扰

// --- [模块3：诱导与维护参数] ---
const long DROP_INTERVAL = 1800000;    // 30分钟定时背景给水维护 (ms)
const int DROP_DURATION = 300;         // 维护给水阀开启时长
const int INITIAL_DROP_MS = 200;         // 实验启动瞬间挂水时长
const long INACTIVITY_LIMIT = 600000;  // 10分钟长静默阈值
const int INACTIVITY_DROP_MS = 150;    // 唤醒诱导给水时长

// --- [模块4：识别与抗噪参数 (双锁核心)] ---
// 【生理锁】：基于小鼠 12Hz 舔舐极限设定的不应期。任何短于 85ms 的连续触发皆为伪影
const int REFR_MS = 85;                
const int DEAD_ZONE = 100;             // 侧向切换死区/互斥锁时间
const int LED_FLASH_MS = 30;           // LED 点亮时长(ms)const int TDT_SYNC_PRINT_EVERY = 10;   // TDT同步信号每 N 次打印一次摘要（1Hz×10=每10s一行）
// --- [模块5：系统运行状态与记忆变量] ---
unsigned long experimentStartTime = 0;
unsigned long rewardT0 = 0;            
unsigned long last_any_lick_time = 0;  
unsigned long last_drop_time = 0;      
unsigned long priming_off_time = 0;    

unsigned long last_lick_s1 = 0;        
unsigned long last_lick_s2 = 0;

// 【物理锁】：边沿检测记忆变量
int s1_last_val = LOW;
int s2_last_val = LOW;

int totalRewards = 0;
int s1RewardCount = 0;
int s2RewardCount = 0;
long s1TotalLicks = 0;                 
long s2TotalLicks = 0;                 

bool is_armed = false;                 
bool is_priming_active = false;        
bool is_v1_open = false, is_v2_open = false;
bool is_drop_open = false, is_flushing = false, is_trig_active = false;
bool is_led_active = false;            

unsigned long v1_start = 0, v2_start = 0, trig_stop = 0, drop_start = 0, led_stop = 0;

// TDT同步信号状态记忆
int tdt_last_val = LOW;
unsigned long tdt_sync_count = 0;

void setup() {
  pinMode(TOUCH_1_PIN, INPUT);   
  pinMode(TOUCH_2_PIN, INPUT);   
  pinMode(VALVE_1_PIN, OUTPUT);
  pinMode(VALVE_2_PIN, OUTPUT);
  pinMode(TRIGGER_PIN, OUTPUT); 
  pinMode(VALVE_DROP_PIN, OUTPUT);
  pinMode(LED_PIN, OUTPUT);      
  pinMode(PAUSE_BUTTON_PIN, INPUT_PULLUP);
  pinMode(TDT_SYNC_PIN, INPUT);      // ← 新增：D44 设为输入
  
  Serial.begin(115200);
  Serial.println(F("======================================================"));
  Serial.println(F("SYSTEM V6.10: EDGE DETECTION + 12Hz BIOLOGICAL LIMIT"));
  Serial.println(F("Format: Time | Spout | Event | TTL | Val | Rew[T/150] | Licks[S1|S2]"));
  Serial.println(F("======================================================"));
  last_drop_time = millis();
}

void loop() {
  unsigned long now = millis();

  // --- 6.1 串口实时指令控制逻辑 ---
  if (Serial.available() > 0) {
    char cmd = Serial.read();
    if (cmd == 'f' || cmd == 'F') { 
      is_flushing = true; stopAll();
      digitalWrite(VALVE_1_PIN, HIGH); digitalWrite(VALVE_2_PIN, HIGH); digitalWrite(VALVE_DROP_PIN, HIGH);
      Serial.println(F("\n>>>> [MODE] FLUSH: 阀门全开，换水维护中 <<<<"));
    }
    else if (cmd == 'n' || cmd == 'N') { 
      is_flushing = false; stopAll();
      Serial.println(F("\n>>>> [MODE] NORMAL: 回归实验监测逻辑 <<<<"));
    }
    else if (cmd == 'z' || cmd == 'Z') { 
      if (!is_flushing) {
        experimentStartTime = now; last_any_lick_time = now;
        totalRewards = 0; s1RewardCount = 0; s2RewardCount = 0;
        s1TotalLicks = 0; s2TotalLicks = 0;
        s1_last_val = LOW; s2_last_val = LOW; // 实验重置时同步清理状态记忆
        rewardT0 = 0; is_armed = true;
        
        if (INITIAL_DROP_MS > 0) {
            digitalWrite(VALVE_1_PIN, HIGH); digitalWrite(VALVE_2_PIN, HIGH);
            is_priming_active = true; priming_off_time = now + INITIAL_DROP_MS;
        }
        Serial.println(F("\n>>>> [EVENT] RESET: 实验开始 <<<<"));
      }
    }
    else if (cmd == 'e' || cmd == 'E') { 
      is_flushing = false; stopAll(); experimentStartTime = 0;
      Serial.println(F("\n>>>> [EVENT] END: 实验手动安全停止 <<<<"));
    }
  }

  // --- 6.2 核心业务与抗噪逻辑 ---
  if (!is_flushing && experimentStartTime > 0) {
    unsigned long relTime = now - experimentStartTime;
    
    // A. 试次间歇 (ITI) 恢复
    if (!is_armed && (now - rewardT0 >= ITI_MS)) {
      is_armed = true;
      Serial.print(relTime); Serial.println(F("\t| SYSTEM\t| ARMED\t| Trial ready"));
    }

    // B. 长静默自动诱导唤醒
    if (is_armed && !is_priming_active && (now - last_any_lick_time >= INACTIVITY_LIMIT)) {
      digitalWrite(VALVE_1_PIN, HIGH); digitalWrite(VALVE_2_PIN, HIGH);
      is_priming_active = true; priming_off_time = now + INACTIVITY_DROP_MS;
      last_any_lick_time = now;
      Serial.print(relTime); Serial.println(F("\t| SYSTEM\t| PRIMING\t| 10min Inactivity Wake-up"));
    }

    // C. 诱导阀门关闭
    if (is_priming_active && now >= priming_off_time) {
      digitalWrite(VALVE_1_PIN, LOW); digitalWrite(VALVE_2_PIN, LOW);
      is_priming_active = false;
    }

    // D. 行为识别 (双锁验证：上升沿 + 生理不应期)
    int s1_val = digitalRead(TOUCH_1_PIN);
    int s2_val = digitalRead(TOUCH_2_PIN);

    if (now - rewardT0 > STABILIZE_MS) {
      
      // --- 水嘴 1 处理 ---
      // [锁1]: s1_val == HIGH && s1_last_val == LOW (必须是触碰的瞬间)
      // [锁2]: now - last_lick_s1 > REFR_MS (距离上次触碰必须大于 85ms)
      if (s1_val == HIGH && s1_last_val == LOW && (now - last_lick_s1 > REFR_MS) && (now - last_lick_s2 > DEAD_ZONE)) {
        last_lick_s1 = now; last_any_lick_time = now; s1TotalLicks++; 
        sendTTL(10); triggerLED();

        if (is_armed && !is_priming_active && totalRewards < MAX_TOTAL_REWARDS) {
          rewardT0 = now; is_armed = false; totalRewards++; s1RewardCount++;
          digitalWrite(VALVE_1_PIN, HIGH); is_v1_open = true; v1_start = now;
          logEvent(relTime, "S1", "REWARD_ON(T0)", "10ms", 1);
        } else {
          logEvent(relTime, "S1", "LICK_ONLY", "10ms", 1);
        }
      }

      // --- 水嘴 2 处理 ---
      if (s2_val == HIGH && s2_last_val == LOW && (now - last_lick_s2 > REFR_MS) && (now - last_lick_s1 > DEAD_ZONE)) {
        last_lick_s2 = now; last_any_lick_time = now; s2TotalLicks++; 
        sendTTL(30); triggerLED();

        if (is_armed && !is_priming_active && totalRewards < MAX_TOTAL_REWARDS) {
          rewardT0 = now; is_armed = false; totalRewards++; s2RewardCount++;
          digitalWrite(VALVE_2_PIN, HIGH); is_v2_open = true; v2_start = now;
          logEvent(relTime, "S2", "REWARD_ON(T0)", "30ms", 1);
        } else {
          logEvent(relTime, "S2", "LICK_ONLY", "30ms", 1);
        }
      }
    }
    
    // 同步更新边缘检测状态
    s1_last_val = s1_val;
    s2_last_val = s2_val;
  }

  // --- 6.3 定时背景给水维护 ---
  if (!is_flushing) {
    if (!is_drop_open && (now - last_drop_time >= DROP_INTERVAL)) {
      digitalWrite(VALVE_DROP_PIN, HIGH); is_drop_open = true;
      drop_start = now; last_drop_time = now;
      if (experimentStartTime > 0) { 
        Serial.print(now - experimentStartTime); Serial.println(F("\t| SYSTEM\t| AUTO_DROP\t| Maintenance Drip")); 
      }
    }
    if (is_drop_open && (now - drop_start >= DROP_DURATION)) {
      digitalWrite(VALVE_DROP_PIN, LOW); is_drop_open = false;
    }
  }

  // --- 6.4 TDT同步信号接收（上升沿检测，每 N 次打印一次摘要）---
  int tdt_val = digitalRead(TDT_SYNC_PIN);
  if (tdt_val == HIGH && tdt_last_val == LOW) {
    tdt_sync_count++;
    // 第1次必印（确认信号已到达），此后每 TDT_SYNC_PRINT_EVERY 次打印一次摘要
    if (tdt_sync_count == 1 || tdt_sync_count % TDT_SYNC_PRINT_EVERY == 0) {
      if (experimentStartTime > 0) {
        unsigned long relTime = now - experimentStartTime;
        Serial.print(relTime);
        Serial.print(F("\t| TDT\t| SYNC_x"));
        Serial.print(TDT_SYNC_PRINT_EVERY);
        Serial.print(F("\t| --\t| --\t| Count:"));
        Serial.println(tdt_sync_count);
      } else {
        Serial.print(F("PRE_EXP\t| TDT\t| SYNC_x"));
        Serial.print(TDT_SYNC_PRINT_EVERY);
        Serial.print(F("\t| --\t| --\t| Count:"));
        Serial.println(tdt_sync_count);
      }
    }
  }
  tdt_last_val = tdt_val;

  updateHardware(now);
}

// --- [模块7：功能函数库] ---

void triggerLED() {
  digitalWrite(LED_PIN, HIGH);
  led_stop = millis() + LED_FLASH_MS;
  is_led_active = true;
}

void sendTTL(int ms) {
  digitalWrite(TRIGGER_PIN, HIGH);
  trig_stop = millis() + ms; 
  is_trig_active = true;
}

void logEvent(unsigned long ts, String src, String desc, String sync, int val) {
  Serial.print(ts); Serial.print(F("\t| "));
  Serial.print(src); Serial.print(F("\t| "));
  Serial.print(desc); Serial.print(F("\t| "));
  Serial.print(sync); Serial.print(F("\t| "));
  Serial.print(val);  Serial.print(F("\t| "));
  Serial.print(totalRewards); Serial.print(F("/150("));
  Serial.print(s1RewardCount); Serial.print(F("|"));
  Serial.print(s2RewardCount); Serial.print(F(") | Licks:"));
  Serial.print(s1TotalLicks); Serial.print(F("|"));
  Serial.print(s2TotalLicks); Serial.println();
}

void updateHardware(unsigned long now) {
  if (is_v1_open && (now - v1_start >= VALVE_ON_MS)) { 
    digitalWrite(VALVE_1_PIN, LOW); is_v1_open = false;
  }
  if (is_v2_open && (now - v2_start >= VALVE_ON_MS)) { 
    digitalWrite(VALVE_2_PIN, LOW); is_v2_open = false;
  }
  if (is_trig_active && now >= trig_stop) { 
    digitalWrite(TRIGGER_PIN, LOW); is_trig_active = false; 
  }
  if (is_led_active && now >= led_stop) {
    digitalWrite(LED_PIN, LOW); is_led_active = false;
  }
}

void stopAll() {
  digitalWrite(VALVE_1_PIN, LOW); digitalWrite(VALVE_2_PIN, LOW);
  digitalWrite(VALVE_DROP_PIN, LOW); digitalWrite(TRIGGER_PIN, LOW);
  digitalWrite(LED_PIN, LOW); 
  is_v1_open = is_v2_open = is_drop_open = is_trig_active = is_priming_active = is_led_active = false;
}