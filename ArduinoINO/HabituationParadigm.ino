/*
 * ============================================================================================
 * Arduino Mega 适应期行为实验系统 (Habituation Paradigm - Day -7 to -4)
 * 功能：纯液体随机发放 (50个 trial)。无背景滴水。所有连线和同步机制与正式脚本完全一致。
 * ============================================================================================
 */

// --- [引脚配置] ---
const int TOUCH_S_1     = A1;     // 输入: 舔水传感器
const int VALVE_MAIN    = 30;     // 输出: 液体电磁阀
const int SHOCK_PIN     = 50;     // 输出: 恒流电击 (保留物理接口方便'k'键测试)
const int LICK_LED_PIN  = 44;     // 输出: 联系黄灯 (舔舐闪烁)
const int TTL_OUT_PIN   = 40;     // 输出: 发往 TDT C0 (宏观刺激标记)
const int LED_PIN       = 7;      // 输出: 宏观液体刺激和电击刺激事件同步红外LED灯

// --- [时序参数 (ms)] ---
const unsigned long TIME_INIT_WAIT  = 20000;  
const unsigned long TOTAL_TRIALS    = 50;     
const unsigned long MIN_ITI         = 10000;  
const unsigned long MAX_ITI         = 20000;  

const unsigned long TIME_PRE_STIM   = 3000;   
const unsigned long VALVE_ON_DUR    = 200;    
const unsigned long TIME_POST_STIM  = 5000;   
const unsigned long START_TTL_DUR   = 50; 
const unsigned long SHOCK_ON_DUR    = 500;    // 手动 k 键使用

// --- [防抖] ---
const int REFR_MS = 85;             
int t1_last_val = LOW;
unsigned long last_lick_t1 = 0;
long totalLicks = 0;
bool is_flushing = false;

// --- [状态机] ---
enum ExpState { IDLE, INIT_WAIT, TRIAL_ITI, TRIAL_PRE, TRIAL_POST, DONE };
ExpState currentState = IDLE;
unsigned long sessionStartTime = 0;  
unsigned long stateStartTime = 0;    
unsigned long currentITI = 0;        
int currentTrialCount = 0;           

void setup() {
  Serial.begin(115200);
  pinMode(TOUCH_S_1, INPUT);
  pinMode(VALVE_MAIN, OUTPUT);
  pinMode(SHOCK_PIN, OUTPUT);
  pinMode(LICK_LED_PIN, OUTPUT);
  pinMode(TTL_OUT_PIN, OUTPUT);
  pinMode(LED_PIN, OUTPUT);

  digitalWrite(VALVE_MAIN, LOW); digitalWrite(SHOCK_PIN, LOW);
  digitalWrite(LICK_LED_PIN, LOW); digitalWrite(TTL_OUT_PIN, LOW); digitalWrite(LED_PIN, LOW);

  randomSeed(analogRead(A5)); 

  Serial.println(F("======================================================"));
  Serial.println(F("HABITUATION SYSTEM: 50 TRIALS (Hub-Sync Edition)"));
  Serial.println(F("======================================================"));
}

void loop() {
  unsigned long now = millis();
  checkSerial(now);
  checkLick(now);
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
        Serial.print(globalTs); Serial.println(F("\t| SYSTEM\t| STATE_CHANGE\t| Start 50 Habituation Trials"));
        currentState = TRIAL_ITI; currentTrialCount = 0; currentITI = random(MIN_ITI, MAX_ITI); stateStartTime = now;
        Serial.print(globalTs); Serial.print(F("\t| SYSTEM\t| TRIAL_ITI\t| ITI duration: ")); Serial.println(currentITI);
      }
      break;

    case TRIAL_ITI:
      if (elapsed >= currentITI) {
        currentState = TRIAL_PRE; stateStartTime = now;
        Serial.print(globalTs); Serial.println(F("\t| SYSTEM\t| TRIAL_EVENT\t| PRE_STIM (3s wait)"));
      }
      break;

    case TRIAL_PRE:
      if (elapsed >= TIME_PRE_STIM) {
        Serial.print(globalTs); Serial.println(F("\t| SYSTEM\t| STIMULUS_ON\t| Liquid Valve OPEN (200ms)"));
        fireValve();
        currentState = TRIAL_POST; stateStartTime = now;
      }
      break;

    case TRIAL_POST:
      if (elapsed >= TIME_POST_STIM) {
        currentTrialCount++;
        Serial.print(globalTs); Serial.print(F("\t| SYSTEM\t| TRIAL_END\t| Progress: ")); Serial.print(currentTrialCount); Serial.print(F("/")); Serial.println(TOTAL_TRIALS);
        if (currentTrialCount >= TOTAL_TRIALS) {
          Serial.print(globalTs); Serial.println(F("\t| SYSTEM\t| STATE_CHANGE\t| 50 Trials Completed. Waiting for manual 'e' exit."));
          currentState = DONE; 
        } else {
          currentState = TRIAL_ITI; currentITI = random(MIN_ITI, MAX_ITI);
          Serial.print(globalTs); Serial.print(F("\t| SYSTEM\t| TRIAL_ITI\t| Next ITI duration: ")); Serial.println(currentITI);
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

void fireValve() {
  digitalWrite(VALVE_MAIN, HIGH); digitalWrite(LED_PIN, HIGH); digitalWrite(TTL_OUT_PIN, HIGH);
  stim_stop = millis() + VALVE_ON_DUR; is_stim_running = true;
}

void fireShock() {
  digitalWrite(SHOCK_PIN, HIGH); digitalWrite(LED_PIN, HIGH); digitalWrite(TTL_OUT_PIN, HIGH);
  shock_stop = millis() + SHOCK_ON_DUR; is_shock_running = true;
}

void fireStartTTL() {
  digitalWrite(TTL_OUT_PIN, HIGH);
  start_ttl_stop = millis() + START_TTL_DUR; is_start_ttl_running = true;
}

void fireLickLED() {
  digitalWrite(LICK_LED_PIN, HIGH);
  lick_led_stop = millis() + 30; is_lick_led_running = true;
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
    if (!is_stim_running && !is_shock_running) { digitalWrite(TTL_OUT_PIN, LOW); }
    is_start_ttl_running = false;
  }
  if (is_lick_led_running && now >= lick_led_stop) {
    digitalWrite(LICK_LED_PIN, LOW);
    is_lick_led_running = false;
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
        fireStartTTL(); 
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
      fireLickLED(); 
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
