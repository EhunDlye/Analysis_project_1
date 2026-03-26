import cv2
import serial
import time
import threading
import queue
import pandas as pd
import sys
import os

# ==========================================
# [配置参数区] - 运行前请务必检查并修改
# ==========================================
SERIAL_PORT = 'COM3'         # Windows 例: 'COM3'; Mac/Linux 例: '/dev/ttyACM0'
BAUD_RATE = 115200           # 必须与 Arduino 代码保持一致 
CAMERA_INDEX = 1             # 摄像头索引 (运行 ScanCameras.py 可查看名称与索引对应关系)
RESOLUTION = (1920, 1080)    # 视频分辨率 (1080p)
TARGET_FPS = 60.0            # 目标帧率
STATUS_INTERVAL = 30.0       # 实时监控控制台刷新间隔（秒）
FRAME_DROP_GAP_FACTOR = 1.8  # 丢帧判定阈值系数：若两帧间隔 > 理论间隔*该系数，判定为异常间隔
FPS_VERIFY_MIN_FRAMES = 120  # 录制后最少采集多少帧再给出一次实测FPS确认
CAMERA_INIT_TIMEOUT = 10.0   # 摄像头首帧超时（秒），超时自动退出
STARTUP_WATCHDOG_TIMEOUT = 30.0  # 脚本启动后若N秒内未出现预览帧则自动退出（防止卡死）

# --- 启动后录制触发方式 ---
# "sync"      : 等待 Arduino 串口收到 TDT SYNC 信号后自动开始（推荐，确保 TDT 已在录制）
# "countdown" : 按 S 后倒计时 PRE_RECORDING_COUNTDOWN 秒再开始（不连 TDT 时使用）
# "immediate" : 按 S 后立即开始
RECORDING_TRIGGER_MODE = 'sync'      # 推荐使用 'sync'
PRE_RECORDING_COUNTDOWN = 10  # countdown 模式下的倒计时秒数（sync 模式下无效）

# --- UI 叠加设置 ---
SAVE_UI_TO_VIDEO = False      # True = 视频文件中保留文字信息；False = 保存纯净视频
UI_FONT_SCALE_L  = 0.65      # 第1行（状态/帧数）字体大小
UI_FONT_SCALE_M  = 0.55      # 第2-3行（时间戳）字体大小
UI_FONT_SCALE_S  = 0.45      # 第4行（Arduino消息）字体大小
PREVIEW_WIDTH    = 960        # 预览窗口宽度（960=原始1920的一半，可自由调整）
PREVIEW_HEIGHT   = 540        # 预览窗口高度（540=原始1080的一半）

# --- 输出文件夹设置 ---
OUTPUT_DIR = r'C:\LZQ\VS_CODE\VideoOutput'  # 数据输出根目录
OUTPUT_FOLDER_NAME = 'experiment_output_pixel-N-4_3.25-8s'  # 输出文件夹名称
OUTPUT_PATH = os.path.join(OUTPUT_DIR, OUTPUT_FOLDER_NAME)
os.makedirs(OUTPUT_PATH, exist_ok=True)  # 若文件夹不存在则自动创建
print(f"📁 数据将保存至: {OUTPUT_PATH}")

VIDEO_OUT_FILE = os.path.join(OUTPUT_PATH, 'behavior_video.mp4')
FRAME_CSV_FILE = os.path.join(OUTPUT_PATH, 'video_timestamps.csv')
SERIAL_CSV_FILE = os.path.join(OUTPUT_PATH, 'arduino_events.csv')
HEALTH_CSV_FILE = os.path.join(OUTPUT_PATH, 'video_health_report.csv')

# ==========================================
# [全局变量与队列]
# ==========================================
is_running = True               # 控制程序整体运行
recording_event = threading.Event()  # 录制状态（.is_set()=录制中，其他线程立即可见）
frame_queue = queue.Queue()  # 用于主线程向写入线程传递视频帧
frame_metadata = []          # 记录每一帧的序号和时间戳
serial_data = []             # 记录 Arduino 发送的事件和时间戳
recording_start_time = None  # 录制开始的精确时间点
data_lock = threading.Lock() # 保护共享列表的线程锁

# sync 模式：等待 TDT SYNC 信号的 Event（由串口线程触发）
tdt_sync_received_event = threading.Event()
# 启动看门狗：首帧成功后置位
first_preview_frame_event = threading.Event()
# 丢帧告警限流：记录上次打印告警的时间（避免每帧都打印拖慢主循环）
_last_drop_warn_time = 0.0
DROP_WARN_INTERVAL = 5.0  # 控制台丢帧告警最小间隔（秒），不影响记录到内存列表

# ==========================================
# [线程 1：串口监听线程]
# ==========================================
def serial_listener_thread(ser):
    global is_running, recording_start_time
    print("[串口线程] 串口监听已启动，等待 Arduino 数据...", flush=True)
    while is_running:
        try:
            if ser.in_waiting > 0:
                raw_line = ser.readline().decode('utf-8', errors='ignore').strip()
                receive_time = time.perf_counter()

                if raw_line:
                    # sync 模式：检测到任意 SYNC 消息时触发事件（让主线程自动开始录制）
                    if "SYNC" in raw_line:
                        tdt_sync_received_event.set()

                    # 用 threading.Event 原子读取录制状态，跨线程可见性有保证
                    recording = recording_event.is_set()
                    t0 = recording_start_time if recording else None

                    if recording and t0 is not None:
                        elapsed_sec = receive_time - t0
                        elapsed_ms  = elapsed_sec * 1000.0
                        tag = f"REC +{elapsed_sec:.4f}s ({elapsed_ms:.1f}ms)"
                    else:
                        elapsed_sec = None
                        elapsed_ms  = None
                        tag = "PREVIEW"

                    # 查找此时最近的视频帧（用局部快照避免长时间持锁）
                    frame_info = ""
                    nearest_frame_idx = None
                    nearest_frame_sys_ts = None
                    nearest_frame_elapsed_sec = None
                    nearest_frame_elapsed_ms  = None

                    if recording and t0 is not None:
                        with data_lock:
                            snap = frame_metadata[-1] if frame_metadata else None
                        if snap is not None:
                            nearest_frame_idx        = snap["frame_index"]
                            nearest_frame_sys_ts     = snap["system_timestamp_sec"]
                            nearest_frame_elapsed_sec = nearest_frame_sys_ts - t0
                            nearest_frame_elapsed_ms  = nearest_frame_elapsed_sec * 1000.0
                            frame_info = (f"  →  视频帧 #{nearest_frame_idx}"
                                          f"  视频时间 +{nearest_frame_elapsed_sec:.4f}s"
                                          f" ({nearest_frame_elapsed_ms:.1f}ms)"
                                          f"  [系统时间: {nearest_frame_sys_ts:.6f}]")

                    # TDT SYNC 消息仅记录到CSV，不打印到控制台（避免每秒1条淹没输出）
                    if "SYNC" not in raw_line:
                        print(f"  ↳ [Arduino | {tag}] {raw_line}{frame_info}", flush=True)

                    if recording and t0 is not None:
                        with data_lock:
                            serial_data.append({
                                # 系统绝对时间戳（perf_counter，秒）
                                "system_timestamp_sec":          receive_time,
                                # 相对录制开始的时间（秒 & 毫秒，方便后期对齐）
                                "recording_elapsed_sec":         elapsed_sec,
                                "recording_elapsed_ms":          elapsed_ms,
                                "arduino_msg":                   raw_line,
                                # 事件发生时最近视频帧信息
                                "nearest_frame_index":           nearest_frame_idx,
                                "nearest_frame_sys_ts_sec":      nearest_frame_sys_ts,
                                "nearest_frame_elapsed_sec":     nearest_frame_elapsed_sec,
                                "nearest_frame_elapsed_ms":      nearest_frame_elapsed_ms,
                            })
        except Exception as e:
            print(f"[串口线程] 错误: {e}", flush=True)
            # 不退出线程，继续监听，避免单次错误导致后续数据全部丢失
            time.sleep(0.01)
            continue

# ==========================================
# [线程 2：视频写入线程]
# ==========================================
def video_writer_thread(fps, width, height):
    global is_running
    print("[Video Thread] 视频编码与写入已启动...")
    fourcc = cv2.VideoWriter_fourcc(*'mp4v') # H.264 / mp4v 编码
    out = cv2.VideoWriter(VIDEO_OUT_FILE, fourcc, fps, (width, height))
    
    while is_running or not frame_queue.empty():
        try:
            # 阻塞式等待获取帧，超时1秒避免死锁
            frame = frame_queue.get(timeout=1.0)
            out.write(frame)
            frame_queue.task_done()
        except queue.Empty:
            continue
            
    out.release()
    print("[视频线程] 视频文件已安全保存。")

# ==========================================
# [线程 3：实时状态监控线程]
# ==========================================
def status_reporter_thread():
    """每隔 STATUS_INTERVAL 秒向控制台打印一次录制状态摘要。"""
    global is_running, recording_start_time
    while is_running:
        time.sleep(STATUS_INTERVAL)
        try:
            recording = recording_event.is_set()
            t0 = recording_start_time
            if not recording or t0 is None:
                print(f"  ○ [监控] PREVIEW 中 | 等待按 S 键开始录制（需先点击摄像头窗口）...", flush=True)
                continue

            elapsed = time.perf_counter() - t0
            with data_lock:
                frame_count  = len(frame_metadata)
                serial_count = len(serial_data)
                recent = serial_data[-5:]
                if frame_metadata:
                    lf = frame_metadata[-1]
                    latest_frame_idx          = lf["frame_index"]
                    latest_frame_elapsed_sec  = lf["video_elapsed_sec"]
                    latest_frame_elapsed_ms   = lf["video_elapsed_ms"]
                    latest_frame_sys_ts       = lf["system_timestamp_sec"]
                else:
                    latest_frame_idx = latest_frame_elapsed_sec = latest_frame_elapsed_ms = latest_frame_sys_ts = None

            actual_fps = frame_count / elapsed if elapsed > 0 else 0.0

            print("\n" + "═" * 70)
            print(f"  ● 实时监控  | 录制中 | 已录制 {elapsed:.1f}s")
            print(f"  ├─ 视频帧数    : 第 {frame_count} 帧  (实测 {actual_fps:.1f} fps)")
            if latest_frame_idx is not None:
                print(f"  ├─ 最新帧    : 帧#{latest_frame_idx}"
                      f"  视频时间 +{latest_frame_elapsed_sec:.4f}s ({latest_frame_elapsed_ms:.1f}ms)"
                      f"  [系统时间: {latest_frame_sys_ts:.6f}]")
            print(f"  ├─ Arduino 事件: 共 {serial_count} 条")
            if recent:
                print(f"  └─ 最近 {len(recent)} 条消息:")
                for e in recent:
                    t_sec  = e.get('recording_elapsed_sec')
                    t_ms   = e.get('recording_elapsed_ms')
                    fi     = e.get('nearest_frame_index')
                    fts_ms = e.get('nearest_frame_elapsed_ms')
                    sys_ts = e.get('system_timestamp_sec')
                    ts_str    = f"+{t_sec:.4f}s ({t_ms:.1f}ms) [系统:{sys_ts:.6f}]" if t_sec is not None else "?"
                    frame_str = f"帧#{fi} +{fts_ms:.1f}ms" if fi is not None else ""
                    print(f"       [{ts_str}] {e['arduino_msg']}  →  {frame_str}")
            else:
                print(f"  └─ 最近消息    : 暂无")
            print("═" * 70 + "\n", flush=True)
        except Exception as e:
            print(f"[监控线程] 错误: {e}", flush=True)


def print_video_health_report(frame_rows, drop_rows, expected_fps, expected_interval_sec, drop_threshold_sec):
    total_frames = len(frame_rows)
    if total_frames < 2:
        print("\n📋 [视频健康报告] 帧数不足，无法进行间隔健康评估（少于2帧）。", flush=True)
        return

    intervals = [r["frame_interval_sec"] for r in frame_rows if r.get("frame_interval_sec") is not None]
    valid_intervals = [v for v in intervals if v is not None and v > 0]
    if not valid_intervals:
        print("\n📋 [视频健康报告] 未获得有效帧间隔数据。", flush=True)
        return

    avg_interval_sec = sum(valid_intervals) / len(valid_intervals)
    measured_fps = (1.0 / avg_interval_sec) if avg_interval_sec > 0 else 0.0
    max_gap_sec = max(valid_intervals)
    min_gap_sec = min(valid_intervals)

    total_drop_events = len(drop_rows)
    estimated_dropped_frames = sum(r.get("estimated_dropped_frames", 0) for r in drop_rows)
    healthy_ratio = (1.0 - total_drop_events / len(valid_intervals)) * 100.0 if valid_intervals else 0.0

    print("\n" + "═" * 82)
    print("📋 视频数据健康报告")
    print(f"  目标参数: {expected_fps:.3f} fps | 理论帧间隔 {expected_interval_sec*1000.0:.3f} ms")
    print(f"  判定阈值: 间隔 > {drop_threshold_sec*1000.0:.3f} ms (系数 {FRAME_DROP_GAP_FACTOR:.2f})")
    print(f"  统计概览: 总帧数={total_frames}, 有效间隔={len(valid_intervals)}, 异常间隔={total_drop_events}")
    print(f"  实测结果: 平均间隔={avg_interval_sec*1000.0:.3f} ms, 实测FPS={measured_fps:.3f}")
    print(f"  极值范围: 最小间隔={min_gap_sec*1000.0:.3f} ms, 最大间隔={max_gap_sec*1000.0:.3f} ms")
    print(f"  健康评分: {healthy_ratio:.2f}% 正常间隔 | 估算丢帧总数={estimated_dropped_frames}")

    if drop_rows:
        print("  异常明细（完整）:")
        for i, ev in enumerate(drop_rows, start=1):
            print(
                f"    #{i:03d} 帧#{ev['prev_frame_index']}→#{ev['curr_frame_index']} | "
                f"视频时间 {ev['gap_start_video_sec']:.4f}s→{ev['gap_end_video_sec']:.4f}s | "
                f"间隔 {ev['gap_sec']*1000.0:.3f} ms | 估算丢帧 {ev['estimated_dropped_frames']}"
            )
    else:
        print("  异常明细: 未发现疑似丢帧间隔。")

    print("═" * 82 + "\n", flush=True)

# ==========================================
# [主程序]
# ==========================================
def main():
    global is_running, recording_start_time
    
    # ── 0. 启动时清理残留的 VideoRecord 进程（排除自身，避免僵尸进程占用摄像头/串口）──
    import subprocess, os
    current_pid = os.getpid()
    try:
        result = subprocess.run(
            ['wmic', 'process', 'where',
             f'name="python.exe" and commandline like "%VideoRecord%"',
             'get', 'processid', '/format:list'],
            capture_output=True, text=True, timeout=5
        )
        for line in result.stdout.splitlines():
            line = line.strip()
            if line.startswith("ProcessId="):
                pid = int(line.split('=')[1])
                if pid != current_pid:
                    try:
                        subprocess.run(['taskkill', '/F', '/PID', str(pid)],
                                       capture_output=True, timeout=3)
                        print(f"  [启动清理] 已终止残留进程 PID={pid}", flush=True)
                    except Exception:
                        pass
    except Exception:
        pass  # wmic 不可用时跳过，不影响主流程

    # 1. 初始化串口
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=1)
        time.sleep(1)  # 等待 Arduino 重启稳定（从2s降至1s）
    except Exception as e:
        print(f"❌ 无法连接串口 {SERIAL_PORT}: {e}")
        sys.exit(1)
        
    # 2. 初始化摄像头（使用 DirectShow 后端 + MJPG 压缩，防止 MSMF 阻塞且降低 USB 带宽）
    print(f"⏳ 正在初始化摄像头 (Index {CAMERA_INDEX}, DSHOW+MJPG)...", flush=True)
    cap = cv2.VideoCapture(CAMERA_INDEX, cv2.CAP_DSHOW)
    cam_label = f"Index {CAMERA_INDEX}"

    if not cap.isOpened():
        print(f"❌ 无法打开摄像头 {cam_label}")
        print("   请先运行 ScanCameras.py 确认可用索引，再修改配置区的 CAMERA_INDEX。")
        ser.close()
        sys.exit(1)

    # 强制 MJPG 压缩格式（大幅降低 USB 带宽，从 ~3Gbps 降至 ~200Mbps）
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, RESOLUTION[0])
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, RESOLUTION[1])
    cap.set(cv2.CAP_PROP_FPS, TARGET_FPS)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)  # 最小化缓冲，减少延迟

    # 首帧超时保护：如果摄像头在 CAMERA_INIT_TIMEOUT 秒内无法返回有效帧，自动退出
    print(f"⏳ 等待摄像头首帧（超时 {CAMERA_INIT_TIMEOUT}s）...", flush=True)
    init_start = time.time()
    first_frame_ok = False
    while time.time() - init_start < CAMERA_INIT_TIMEOUT:
        ret, _ = cap.read()
        if ret:
            first_frame_ok = True
            break
        time.sleep(0.1)

    if not first_frame_ok:
        print(f"❌ 摄像头在 {CAMERA_INIT_TIMEOUT}s 内未返回有效帧，自动退出。")
        print("   可能原因：摄像头被其他程序占用、USB 连接不稳、驱动异常。")
        print("   建议：关闭所有占用摄像头的程序后重试。")
        cap.release()
        ser.close()
        sys.exit(1)

    actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    actual_fps = cap.get(cv2.CAP_PROP_FPS)
    fourcc_int = int(cap.get(cv2.CAP_PROP_FOURCC))
    fourcc_str = ''.join([chr((fourcc_int >> 8 * i) & 0xFF) for i in range(4)])
    print(f"📷 摄像头就绪: {actual_w}x{actual_h} @ {actual_fps} fps (格式: {fourcc_str}, 后端: DSHOW)")

    # 3. 启动后台子线程
    threading.Thread(target=serial_listener_thread, args=(ser,), daemon=True).start()
    threading.Thread(target=video_writer_thread, args=(actual_fps, actual_w, actual_h), daemon=True).start()
    threading.Thread(target=status_reporter_thread, daemon=True).start()

    # ── 启动看门狗线程：STARTUP_WATCHDOG_TIMEOUT 秒内若未收到第一帧预览则自动退出 ──
    def _startup_watchdog():
        if not first_preview_frame_event.wait(timeout=STARTUP_WATCHDOG_TIMEOUT):
            print(
                f"\n❌ [看门狗] {STARTUP_WATCHDOG_TIMEOUT}s 内未收到摄像头预览帧，程序自动退出。\n"
                f"   可能原因：摄像头被占用、USB 连接不稳、上一次进程未退出。\n"
                f"   解决方法：重新插拔 USB 或重启程序，确认无其他程序占用摄像头。",
                flush=True
            )
            os._exit(1)
    threading.Thread(target=_startup_watchdog, daemon=True).start()

    print("\n" + "="*60)
    print("▶️  实验控制台就绪")
    if RECORDING_TRIGGER_MODE == 'sync':
        print("👉 按 'S' 键: 进入【等待TDT SYNC】模式，检测到同步信号后自动开始")
        print("   ⚠️  在预览窗口点击后按 S，然后在电脑A上开启 TDT 录制即可")
    elif RECORDING_TRIGGER_MODE == 'countdown':
        print(f"👉 按 'S' 键: 倒计时 {PRE_RECORDING_COUNTDOWN}s 后开始录制")
    else:
        print("👉 按 'S' 键: 立即开始录制")
    print("👉 按 'Q' 键: 发送 'E' 结束实验并退出")
    print("="*60 + "\n")

    frame_count = 0
    last_arduino_msg = ""
    last_arduino_elapsed_ms = None
    expected_interval_sec = (1.0 / TARGET_FPS) if TARGET_FPS > 0 else 0.0
    drop_threshold_sec = expected_interval_sec * FRAME_DROP_GAP_FACTOR if expected_interval_sec > 0 else float('inf')
    prev_frame_sys_ts = None
    drop_events = []
    runtime_fps_verified = False
    # 丢帧告警限流状态
    global _last_drop_warn_time
    _pending_drop_count = 0  # 限流期间累积的丢帧事件数

    # 4. 主视觉循环
    cv2.namedWindow("Behavior Camera", cv2.WINDOW_NORMAL)
    cv2.resizeWindow("Behavior Camera", PREVIEW_WIDTH, PREVIEW_HEIGHT)

    while True:
        ret, frame = cap.read()
        if not ret:
            print("⚠️ 无法从摄像头读取画面。")
            break
        
        # 首帧到达，解除看门狗
        first_preview_frame_event.set()
            
        current_time = time.perf_counter()
        
        # 如果正在录制，将帧放入写入队列，并记录元数据
        if recording_event.is_set():
            t0 = recording_start_time  # 局部捕获避免竞态
            if t0 is not None:
                frame_elapsed_sec = current_time - t0
                frame_elapsed_ms  = frame_elapsed_sec * 1000.0
            else:
                frame_elapsed_sec = 0.0
                frame_elapsed_ms  = 0.0

            frame_interval_sec = None
            frame_interval_ms = None
            is_drop_gap = False
            estimated_drop_count = 0

            if prev_frame_sys_ts is not None:
                frame_interval_sec = current_time - prev_frame_sys_ts
                frame_interval_ms = frame_interval_sec * 1000.0
                if expected_interval_sec > 0 and frame_interval_sec > drop_threshold_sec:
                    is_drop_gap = True
                    estimated_drop_count = max(1, int(round(frame_interval_sec / expected_interval_sec)) - 1)
                    drop_event = {
                        "prev_frame_index": frame_count - 1,
                        "curr_frame_index": frame_count,
                        "gap_start_video_sec": frame_elapsed_sec - frame_interval_sec,
                        "gap_end_video_sec": frame_elapsed_sec,
                        "gap_sec": frame_interval_sec,
                        "gap_ms": frame_interval_ms,
                        "estimated_dropped_frames": estimated_drop_count,
                    }
                    drop_events.append(drop_event)
                    _pending_drop_count += 1
                    # 限流：每 DROP_WARN_INTERVAL 秒最多打印一次告警摘要，避免 I/O 拖慢主循环
                    now_warn = time.perf_counter()
                    if now_warn - _last_drop_warn_time >= DROP_WARN_INTERVAL:
                        print(
                            f"⚠️ [丢帧告警] 最近{DROP_WARN_INTERVAL:.0f}s内累积 {_pending_drop_count} 次异常间隔"
                            f"（最新: 帧#{frame_count-1}→#{frame_count} {frame_interval_ms:.1f}ms）",
                            flush=True
                        )
                        _last_drop_warn_time = now_warn
                        _pending_drop_count = 0

            prev_frame_sys_ts = current_time

            # 用局部快照更新 Arduino 最新消息（短暂加锁，立即释放）
            with data_lock:
                frame_metadata.append({
                    "frame_index":          frame_count,
                    "system_timestamp_sec": current_time,
                    "video_elapsed_sec":    frame_elapsed_sec,
                    "video_elapsed_ms":     frame_elapsed_ms,
                    "frame_interval_sec":   frame_interval_sec,
                    "frame_interval_ms":    frame_interval_ms,
                    "is_drop_gap":          is_drop_gap,
                    "estimated_dropped_frames": estimated_drop_count,
                })
                if serial_data:
                    latest_serial = serial_data[-1]
                    last_arduino_msg        = latest_serial.get("arduino_msg", "")
                    last_arduino_elapsed_ms = latest_serial.get("recording_elapsed_ms")

            # 每100帧打印一次进度（使用极简格式，减少终端 I/O）
            if frame_count % 100 == 0 and frame_count > 0:
                print(f"  [视频] #{frame_count:>6d}  +{frame_elapsed_sec:.2f}s", flush=True)

            if (not runtime_fps_verified) and recording_start_time is not None and frame_count >= FPS_VERIFY_MIN_FRAMES:
                elapsed_verify = current_time - recording_start_time
                measured_fps_verify = (frame_count / elapsed_verify) if elapsed_verify > 0 else 0.0
                current_h, current_w = frame.shape[:2]
                print(
                    f"  [录制参数-实测] 已采集{frame_count}帧 | 实测FPS={measured_fps_verify:.3f}"
                    f" | {current_w}x{current_h}",
                    flush=True
                )
                runtime_fps_verified = True

            # ── UI 文字叠加 ──
            status_text   = f"REC  Frame: {frame_count}"
            video_ts_text = f"Video: {frame_elapsed_sec:.3f}s  ({frame_elapsed_ms:.1f}ms)"
            if last_arduino_elapsed_ms is not None:
                ard_text     = f"Arduino: {last_arduino_elapsed_ms/1000:.3f}s  ({last_arduino_elapsed_ms:.1f}ms)"
                ard_msg_text = f"MSG: {last_arduino_msg[:60]}"
            else:
                ard_text     = "Arduino: 等待数据..."
                ard_msg_text = ""
            color = (0, 0, 255)

            display_frame = frame.copy()
            y0, dy = 40, 32
            cv2.putText(display_frame, status_text,   (20, y0),        cv2.FONT_HERSHEY_SIMPLEX, UI_FONT_SCALE_L, color,          2)
            cv2.putText(display_frame, video_ts_text,  (20, y0+dy),     cv2.FONT_HERSHEY_SIMPLEX, UI_FONT_SCALE_M, (0, 200, 255),  1)
            cv2.putText(display_frame, ard_text,       (20, y0+dy*2),   cv2.FONT_HERSHEY_SIMPLEX, UI_FONT_SCALE_M, (0, 255, 180),  1)
            if ard_msg_text:
                cv2.putText(display_frame, ard_msg_text, (20, y0+dy*3), cv2.FONT_HERSHEY_SIMPLEX, UI_FONT_SCALE_S, (200, 200, 200),1)

            frame_to_save = display_frame if SAVE_UI_TO_VIDEO else frame
            frame_queue.put(frame_to_save)
            frame_count += 1

        else:
            # ── 预览模式 ──
            status_text   = "PREVIEW (Press 'S' to Start)"
            color = (0, 255, 0)
            display_frame = frame.copy()
            cv2.putText(display_frame, status_text, (20, 40), cv2.FONT_HERSHEY_SIMPLEX, UI_FONT_SCALE_L, color, 2)

        # 统一预览窗口显示
        cv2.imshow("Behavior Camera", display_frame)

        # 键盘事件监听
        key = cv2.waitKey(1) & 0xFF
        
        if key == ord('s') and not recording_event.is_set():
            if RECORDING_TRIGGER_MODE == 'sync':
                # ── Sync 模式：等待 TDT 发出第一个 SYNC 脉冲后自动开始 ──
                print(f"\n⏰ [等待TDT SYNC] 请立即在电脑A上开启 TDT 录制，检测到同步信号后将自动开始！", flush=True)
                tdt_sync_received_event.clear()  # 清除之前可能已存在的信号
                sync_wait_start = time.time()
                sync_wait_cancelled = False
                while not tdt_sync_received_event.is_set():
                    ret_w, frame_w = cap.read()
                    if ret_w:
                        disp_w = frame_w.copy()
                        elapsed_wait = time.time() - sync_wait_start
                        cv2.putText(disp_w,
                                    f"Waiting for TDT SYNC... ({elapsed_wait:.0f}s)  Press Q to cancel",
                                    (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 165, 255), 2)
                        cv2.imshow("Behavior Camera", disp_w)
                    k_w = cv2.waitKey(100) & 0xFF
                    if k_w == ord('q'):
                        sync_wait_cancelled = True
                        break
                if sync_wait_cancelled:
                    print("🛑 等待期间按下 Q，取消录制。", flush=True)
                    break
                print(f"  ✅ [TDT SYNC 已收到] 自动开始录制！", flush=True)

            elif RECORDING_TRIGGER_MODE == 'countdown':
                # ── Countdown 模式（兼容无TDT场景）──
                print(f"\n⏰ [倒计时] {PRE_RECORDING_COUNTDOWN}s 后开始录制，请立即开启 TDT 录制！", flush=True)
                countdown_start = time.time()
                countdown_cancelled = False
                while True:
                    remaining = PRE_RECORDING_COUNTDOWN - (time.time() - countdown_start)
                    if remaining <= 0:
                        break
                    ret_cd, frame_cd = cap.read()
                    if ret_cd:
                        disp_cd = frame_cd.copy()
                        cd_text = f"STARTING IN {int(remaining)+1}s - Enable TDT NOW!"
                        cv2.putText(disp_cd, cd_text, (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 255), 2)
                        cv2.imshow("Behavior Camera", disp_cd)
                    k_cd = cv2.waitKey(100) & 0xFF
                    if k_cd == ord('q'):
                        countdown_cancelled = True
                        break
                if countdown_cancelled:
                    print("🛑 倒计时期间按下 Q，取消录制。", flush=True)
                    break
            # else: immediate 模式直接继续

            print("\n🎬 [命令] 开始录制！向 Arduino 发送 'Z' 指令...", flush=True)
            ser.write(b'Z')
            recording_start_time = time.perf_counter()
            prev_frame_sys_ts = None
            drop_events.clear()
            runtime_fps_verified = False
            _last_drop_warn_time = 0.0
            _pending_drop_count = 0
            recording_event.set()
            print(f"  [录制] t0 已记录: {recording_start_time:.6f}", flush=True)

            actual_w_rec = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            actual_h_rec = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            actual_fps_rec = cap.get(cv2.CAP_PROP_FPS)
            expected_interval_ms = expected_interval_sec * 1000.0 if expected_interval_sec > 0 else 0.0
            print(
                f"  [录制参数] {actual_w_rec}x{actual_h_rec} | FPS={actual_fps_rec:.3f} | "
                f"理论帧间隔={expected_interval_ms:.3f}ms | 丢帧阈值={drop_threshold_sec*1000.0:.3f}ms",
                flush=True
            )
            
        elif key == ord('q'):
            print("\n🛑 [命令] 结束录制！向 Arduino 发送 'E' 指令...")
            ser.write(b'E')
            break

    # 5. 清理与保存环节
    print("\n⏳ 正在保存数据并清理线程，请稍候...")
    is_running = False
    recording_event.clear()

    cap.release()
    cv2.destroyAllWindows()
    ser.close()
    
    # 保存对齐用的时间戳数据
    if frame_metadata:
        pd.DataFrame(frame_metadata).to_csv(FRAME_CSV_FILE, index=False)
        print(f"✅ 视频帧时间戳已保存至: {FRAME_CSV_FILE}")
    else:
        print("⚠️  视频帧数据为空，未生成 CSV（始终未开始录制？）")
    if serial_data:
        pd.DataFrame(serial_data).to_csv(SERIAL_CSV_FILE, index=False)
        print(f"✅ Arduino 串口数据已保存至: {SERIAL_CSV_FILE}")
    else:
        print("⚠️  Arduino 事件数据为空，未生成 CSV。可能原因：")
        print("    1. 录制期间 Arduino 未发送任何串口数据")
        print("    2. 串口线程操作升级前运行（旧版本线程可见性问题）")

    print_video_health_report(
        frame_rows=frame_metadata,
        drop_rows=drop_events,
        expected_fps=TARGET_FPS,
        expected_interval_sec=expected_interval_sec,
        drop_threshold_sec=drop_threshold_sec,
    )
    if drop_events:
        pd.DataFrame(drop_events).to_csv(HEALTH_CSV_FILE, index=False)
        print(f"✅ 丢帧明细报告已保存至: {HEALTH_CSV_FILE}")
    else:
        print("✅ 未检测到疑似丢帧间隔，本次不生成独立丢帧明细 CSV。")

if __name__ == '__main__':
    main()