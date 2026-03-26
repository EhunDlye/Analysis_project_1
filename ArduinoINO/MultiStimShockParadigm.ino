/*
 * ============================================================================================
 * Arduino Mega 多模态行为实验系统 (v4.2 终极同步版 Single-Liquid Block Paradigm)
 * 硬件变动：TDT 变为接收枢纽 (C0 接 D40)。舔水驱动黄灯 (D44)。宏观刺激驱动蓝灯 (D7)。
 * 同步策略：开场 50ms TTL，给水 200ms TTL，电击 500ms TTL，皆发往 D40。
 * 作者：Antigravity Agent
 * 日期：2026-03-26
 * ============================================================================================
 */

// --- [引脚配置] ---
const int TOUCH_S_1     = A1;     // 输入: 舔水传感器    2号水嘴：A8
const int VALVE_MAIN    = 30;     // 输出: 液体电磁阀    2号电磁阀：D22
const int VALVE_DROP_PIN= 4;      // 输出: 30min 背景滴水电磁阀
const int SHOCK_PIN     = 50;     // 输出: 恒流刺激器触发端
const int LICK_LED_PIN  = 44;     // 输出: 连接黄色LED灯(每次舔舐时闪烁)
const int TTL_OUT_PIN   = 40;     // 输出: 发送 TTL 给 TDT C0 (起始/给水/电击)，pixel电脑发送TTL同步信号到TDT的C3接口进行同步
const int LED_PIN       = 7;      // 输出: 宏观液体刺激和电击刺激事件同步红外LED灯

// --- [时序参数 (ms)] ---
const unsigned long TIME_INIT_WAIT  = 20000;  // Pre-session 前置 20 秒适应
const unsigned long TRIALS_PER_BLOCK= 25;     // 每个 Block 包含 25 个 Trial
const unsigned long MIN_ITI         = 10000;  // 最小随机 ITI (10s)
const unsigned long MAX_ITI         = 20000;  // 最大随机 ITI (20s)

const unsigned long TIME_PRE_STIM   = 3000;   // 刺激前 3s
const unsigned long VALVE_ON_DUR    = 200;    // 电磁阀/LED/TTL 脉宽 200ms
const unsigned long TIME_POST_STIM  = 5000;   // 刺激后 5s 

const unsigned long TIME_WAIT_SHOCK = 60000;  // Block1 -> Shock 60s
const unsigned long TIME_PRE_SHOCK  = 5000;   // Shock 前 5s
const unsigned long SHOCK_ON_DUR    = 500;    // 电击/LED/TTL 脉宽 500ms
const unsigned long TIME_POST_SHOCK = 15000;  // Shock 后 15s
const unsigned long TIME_WAIT_B2    = 60000;  // Shock -> Block2 60s

const unsigned long START_TTL_DUR   = 50;     // 实验开始时的同步基准脉宽 50ms

// --- [背景滴水参数] ---
const unsigned long DROP_INTERVAL   = 1800000;// 30分钟
const unsigned long DROP_DURATION   = 300;    // 滴水持续时间
unsigned long last_drop_time = 0;
bool is_drop_open = false;

// --- [生理双锁与防抖] ---
const int REFR_MS = 85;             
int t1_last_val = LOW;
unsigned long last_lick_t1 = 0;
long totalLicks = 0;
bool is_flushing = false;

// --- [非阻塞状态机引擎] ---
enum ExpState {
  IDLE, INIT_WAIT,
  B1_ITI, B1_PRE_STIM, B1_POST_STIM,
  WAIT_SHOCK, SHOCK_PRE, SHOCK_POST,
  WAIT_B2, B2_ITI, B2_PRE_STIM, B2_POST_STIM,
  DONE
};

ExpState currentState = IDLE;
unsigned long sessionStartTime = 0;  // 发送 's' 的绝对宏观零点
unsigned long stateStartTime = 0;    // 当前子状态进入的毫秒级时钟
unsigned long currentITI = 0;        
int currentTrialCount = 0;           

void setup() {
  Serial.begin(115200);
  pinMode(TOUCH_S_1, INPUT);
  pinMode(VALVE_MAIN, OUTPUT);
  pinMode(VALVE_DROP_PIN, OUTPUT);
  pinMode(SHOCK_PIN, OUTPUT);
  pinMode(LICK_LED_PIN, OUTPUT);
  pinMode(TTL_OUT_PIN, OUTPUT);
  pinMode(LED_PIN, OUTPUT);

  digitalWrite(VALVE_MAIN, LOW);
  digitalWrite(VALVE_DROP_PIN, LOW);
  digitalWrite(SHOCK_PIN, LOW);
  digitalWrite(LICK_LED_PIN, LOW);
  digitalWrite(TTL_OUT_PIN, LOW);
  digitalWrite(LED_PIN, LOW);

  randomSeed(analogRead(A5)); 
  last_drop_time = millis();

  Serial.println(F("======================================================"));
  Serial.println(F("SYSTEM V4.2: SHOCK PARADIGM (Hub-Sync TDT Edition)"));
  Serial.println(F("======================================================"));
}

void loop() {
  unsigned long now = millis();

  checkSerial(now);
  checkLick(now);
  manageBackgroundDrop(now);
  updateHardware(now); 

  if (currentState != IDLE && currentState != DONE) {
    runStateMachine(now);
  }
}

void runStateMachine(unsigned long now) {
  unsigned long elapsed = now - stateStartTime;
  unsigned long globalTs = now - sessionStartTime;

  switch (currentState) {
    case INIT_WAIT:
      if (elapsed >= TIME_INIT_WAIT) {
        Serial.print(globalTs); Serial.println(F("\t| SYSTEM\t| STATE_CHANGE\t| Entering BLOCK_1 (Baseline)"));
        currentState = B1_ITI; currentTrialCount = 0; currentITI = random(MIN_ITI, MAX_ITI); stateStartTime = now;
        Serial.print(globalTs); Serial.print(F("\t| SYSTEM\t| BLOCK_1_ITI\t| ITI duration: ")); Serial.println(currentITI);
      }
      break;

    case B1_ITI:
      if (elapsed >= currentITI) {
        currentState = B1_PRE_STIM; stateStartTime = now;
        Serial.print(globalTs); Serial.println(F("\t| SYSTEM\t| TRIAL_EVENT\t| PRE_STIM (3s wait)"));
      }
      break;

    case B1_PRE_STIM:
      if (elapsed >= TIME_PRE_STIM) {
        Serial.print(globalTs); Serial.println(F("\t| SYSTEM\t| STIMULUS_ON\t| Liquid Valve OPEN (200ms)"));
        fireValve();
        currentState = B1_POST_STIM; stateStartTime = now;
      }
      break;

    case B1_POST_STIM:
      if (elapsed >= TIME_POST_STIM) {
        currentTrialCount++;
        Serial.print(globalTs); Serial.print(F("\t| SYSTEM\t| TRIAL_END\t| Block 1 Progress: ")); Serial.print(currentTrialCount); Serial.print(F("/")); Serial.println(TRIALS_PER_BLOCK);
        if (currentTrialCount >= TRIALS_PER_BLOCK) {
          Serial.print(globalTs); Serial.println(F("\t| SYSTEM\t| STATE_CHANGE\t| Block 1 finished. Entering 60s WAIT_SHOCK silent period."));
          currentState = WAIT_SHOCK;
        } else {
          currentState = B1_ITI; currentITI = random(MIN_ITI, MAX_ITI);
          Serial.print(globalTs); Serial.print(F("\t| SYSTEM\t| BLOCK_1_ITI\t| Next ITI duration: ")); Serial.println(currentITI);
        }
        stateStartTime = now;
      }
      break;

    case WAIT_SHOCK:
      if (elapsed >= TIME_WAIT_SHOCK) {
        currentState = SHOCK_PRE; stateStartTime = now;
        Serial.print(globalTs); Serial.println(F("\t| SYSTEM\t| SHOCK_PHASE\t| SHOCK_PRE (5s quiet before aversive)"));
      }
      break;

    case SHOCK_PRE:
      if (elapsed >= TIME_PRE_SHOCK) {
        Serial.print(globalTs); Serial.println(F("\t| SYSTEM\t| EVENT_CRITICAL\t| SHOCK_ON (500ms)"));
        fireShock();
        currentState = SHOCK_POST; stateStartTime = now;
      }
      break;

    case SHOCK_POST:
      if (elapsed >= TIME_POST_SHOCK) {
        Serial.print(globalTs); Serial.println(F("\t| SYSTEM\t| STATE_CHANGE\t| Shock trial finished. Entering 60s WAIT_B2 recovery period."));
        currentState = WAIT_B2; stateStartTime = now;
      }
      break;

    case WAIT_B2:
      if (elapsed >= TIME_WAIT_B2) {
        Serial.print(globalTs); Serial.println(F("\t| SYSTEM\t| STATE_CHANGE\t| Entering BLOCK_2 (Post-Shock)"));
        currentState = B2_ITI; currentTrialCount = 0; currentITI = random(MIN_ITI, MAX_ITI); stateStartTime = now;
        Serial.print(globalTs); Serial.print(F("\t| SYSTEM\t| BLOCK_2_ITI\t| ITI duration: ")); Serial.println(currentITI);
      }
      break;

    case B2_ITI:
      if (elapsed >= currentITI) {
        currentState = B2_PRE_STIM; stateStartTime = now;
        Serial.print(globalTs); Serial.println(F("\t| SYSTEM\t| TRIAL_EVENT\t| PRE_STIM (3s wait)"));
      }
      break;

    case B2_PRE_STIM:
      if (elapsed >= TIME_PRE_STIM) {
        Serial.print(globalTs); Serial.println(F("\t| SYSTEM\t| STIMULUS_ON\t| Liquid Valve OPEN (200ms)"));
        fireValve();
        currentState = B2_POST_STIM; stateStartTime = now;
      }
      break;

    case B2_POST_STIM:
      if (elapsed >= TIME_POST_STIM) {
        currentTrialCount++;
        Serial.print(globalTs); Serial.print(F("\t| SYSTEM\t| TRIAL_END\t| Block 2 Progress: ")); Serial.print(currentTrialCount); Serial.print(F("/")); Serial.println(TRIALS_PER_BLOCK);
        if (currentTrialCount >= TRIALS_PER_BLOCK) {
          Serial.print(globalTs); Serial.println(F("\t| SYSTEM\t| STATE_CHANGE\t| ALL TRIALS COMPLETE. System entering DONE state. Waiting for 'e'."));
          currentState = DONE; 
        } else {
          currentState = B2_ITI; currentITI = random(MIN_ITI, MAX_ITI);
          Serial.print(globalTs); Serial.print(F("\t| SYSTEM\t| BLOCK_2_ITI\t| Next ITI duration: ")); Serial.println(currentITI);
        }
        stateStartTime = now;
      }
      break;
    default: break;
  }
}

// ==========================================
// [异步硬件触发器]
// ==========================================
unsigned long stim_stop = 0; bool is_stim_running = false;
unsigned long shock_stop = 0; bool is_shock_running = false;
unsigned long start_ttl_stop = 0; bool is_start_ttl_running = false;
unsigned long lick_led_stop = 0; bool is_lick_led_running = false;

// T=0 给水 (200ms)
void fireValve() {
  digitalWrite(VALVE_MAIN, HIGH);
  digitalWrite(LED_PIN, HIGH);
  digitalWrite(TTL_OUT_PIN, HIGH);
  stim_stop = millis() + VALVE_ON_DUR;
  is_stim_running = true;
}

// T=0 电击 (500ms)
void fireShock() {
  digitalWrite(SHOCK_PIN, HIGH);
  digitalWrite(LED_PIN, HIGH);
  digitalWrite(TTL_OUT_PIN, HIGH);
  shock_stop = millis() + SHOCK_ON_DUR;
  is_shock_running = true;
}

// 实验开场 TTL (50ms)
void fireStartTTL() {
  digitalWrite(TTL_OUT_PIN, HIGH);
  start_ttl_stop = millis() + START_TTL_DUR;
  is_start_ttl_running = true;
}

// Lick 触发黄灯 (30ms)
void fireLickLED() {
  digitalWrite(LICK_LED_PIN, HIGH);
  lick_led_stop = millis() + 30;
  is_lick_led_running = true;
}

void updateHardware(unsigned long now) {
  if (is_stim_running && now >= stim_stop) {
    if (!is_flushing) digitalWrite(VALVE_MAIN, LOW); 
    digitalWrite(LED_PIN, LOW); digitalWrite(TTL_OUT_PIN, LOW);
    is_stim_running = false;
  }
  if (is_shock_running && now >= shock_stop) {
    digitalWrite(SHOCK_PIN, LOW); digitalWrite(LED_PIN, LOW); digitalWrite(TTL_OUT_PIN, LOW);
    is_shock_running = false;
  }
  if (is_start_ttl_running && now >= start_ttl_stop) {
    // 确保只有在没有其他事件征用 TTL_OUT_PIN 的时候才关闭
    if (!is_stim_running && !is_shock_running) { digitalWrite(TTL_OUT_PIN, LOW); }
    is_start_ttl_running = false;
  }
  if (is_lick_led_running && now >= lick_led_stop) {
    digitalWrite(LICK_LED_PIN, LOW);
    is_lick_led_running = false;
  }
}

void manageBackgroundDrop(unsigned long now) {
  if (!is_flushing) {
    if (!is_drop_open && (now - last_drop_time >= DROP_INTERVAL)) {
      digitalWrite(VALVE_DROP_PIN, HIGH); is_drop_open = true; last_drop_time = now;
      unsigned long ts = (sessionStartTime > 0) ? (now - sessionStartTime) : 0;
      Serial.print(ts); Serial.println(F("\t| SYSTEM\t| AUTO_DROP\t| 30min Maintenance Drip Executed"));
    }
    if (is_drop_open && (now - last_drop_time >= DROP_DURATION)) {
      digitalWrite(VALVE_DROP_PIN, LOW); is_drop_open = false;
    }
  }
}

// ==========================================
// [通讯与事件]
// ==========================================
void checkSerial(unsigned long now) {
  if (Serial.available() > 0) {
    char cmd = Serial.read();
    unsigned long ts = (sessionStartTime > 0) ? (now - sessionStartTime) : 0;

    if (cmd == 's' || cmd == 'S') { 
      if (!is_flushing && (currentState == IDLE || currentState == DONE)) {
        sessionStartTime = now; stateStartTime = now; currentState = INIT_WAIT; totalLicks = 0; t1_last_val = LOW;
        fireStartTTL(); // 开场 TDT 同步对齐标识
        Serial.print(0); Serial.println(F("\t| SYSTEM\t| COMMAND_START\t| Automaton Initiated, START_TTL SENT"));
      }
    }
    else if (cmd == 'e' || cmd == 'E') { 
      is_flushing = false; stopAndReset();
      Serial.print(ts); Serial.println(F("\t| SYSTEM\t| COMMAND_END\t| Session Aborted/Stopped"));
    }
    else if (cmd == 'f' || cmd == 'F') { 
      is_flushing = true; digitalWrite(VALVE_MAIN, HIGH);
      Serial.print(ts); Serial.println(F("\t| SYSTEM\t| COMMAND_FLUSH\t| Main valve forced OPEN"));
    }
    else if (cmd == 'n' || cmd == 'N') { 
      is_flushing = false; digitalWrite(VALVE_MAIN, LOW);
      Serial.print(ts); Serial.println(F("\t| SYSTEM\t| COMMAND_NORMAL\t| Valve closed"));
    }
    else if (cmd == 'm' || cmd == 'M') { 
      Serial.print(ts); Serial.println(F("\t| SYSTEM\t| COMMAND_MANUAL\t| MANUAL_STIMULUS (Liquid_ON)"));
      fireValve();
    }
    else if (cmd == 'k' || cmd == 'K') { 
      Serial.print(ts); Serial.println(F("\t| SYSTEM\t| COMMAND_MANUAL\t| MANUAL_SHOCK (Shock_ON)"));
      fireShock();
    }
  }
}

void checkLick(unsigned long now) {
  int t1_val = digitalRead(TOUCH_S_1);
  if (t1_val == HIGH && t1_last_val == LOW) { 
    if (now - last_lick_t1 > REFR_MS) {       
      last_lick_t1 = now;
      totalLicks++;
      fireLickLED(); // 舔舐物理硬件反馈 (黄灯闪烁 30ms)
      
      unsigned long ts = (sessionStartTime > 0) ? (now - sessionStartTime) : 0;
      Serial.print(ts); Serial.print(F("\t| S1\t| LICK_EVENT\t| Count:")); Serial.println(totalLicks);
    }
  }
  t1_last_val = t1_val;
}

void stopAndReset() {
  currentState = IDLE;
  digitalWrite(VALVE_MAIN, LOW); digitalWrite(SHOCK_PIN, LOW);
  digitalWrite(LED_PIN, LOW); digitalWrite(TTL_OUT_PIN, LOW); digitalWrite(LICK_LED_PIN, LOW);
  is_stim_running = false; is_shock_running = false; is_lick_led_running = false; is_start_ttl_running = false;
}
