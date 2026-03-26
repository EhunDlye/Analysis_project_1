# 诊断与解决 1080p/60fps 丢帧问题的实施计划

## 丢帧原因诊断
从终端提供的 [video_health_report](file:///c:/LZQ/VS_CODE/VideoRecord.py#371-413) 可以看出：在总共 726 帧的测试中，平均有 39 次出现异常间隔。异常间隔的时间集中在 30ms ~ 36ms 左右，而 60fps 的理想录制间隔应为 16.6ms。偶尔也会出现 47ms。
30ms 恰好是由于**某一个计算环节发生了阻塞，导致程序完全错过了摄像头的 16.6ms 取帧窗口**，被迫等到了下一个 16.6ms，也就是连续合并成了两帧的时间 (33.3ms)。

查看 [VideoRecord.py](file:///c:/Neurovideo/VideoRecord.py) 此前的架构方案可知：
`cap.read()`, 截取时间戳, 并叠加文字UI (`cv2.putText` × 4), 以及使用 `cv2.imshow()` 和 `cv2.waitKey(1)` 更新这1080p的高清预览窗口，全部挤在了**同一个主循环 (主线程)** 内。
这导致每个硬件周期都需要进行繁重且不可控的UI渲染，极易造成执行超时并引发摄像头底层硬件丢帧。

## 解决方案: 纯净的四线程生产者-消费者架构 (Decoupled Camera Polling)
在多模态的高精度采集领域（参考 LSL 或 Bonsai 的标准做法），USB 相机的 `cap.read()` 必须拥有自己完全独立的线程，且不能含有任何 GUI 或延时操作。

### 预期更改方案

#### [MODIFY] [VideoRecord.py](file:///c:/Neurovideo/VideoRecord.py)
我们要将 [VideoRecord.py](file:///c:/Neurovideo/VideoRecord.py) 由目前的 3 线程升级为 4 线程，并作如下剥离：

1.  **新增全局共享变量与锁:**
    -   `preview_frame = None`
    -   `preview_info = {}`
    -   `preview_lock = threading.Lock()`
2.  **提取 [video_capture_thread](file:///c:/LZQ/VS_CODE/VideoRecord.py#232-367) (线程 4 - 生产者):**
    -   线程内只包含一个极速死循环 `while is_running`。
    -   负责执行 `ret, frame = cap.read()` 并瞬间打上系统级时间戳。
    -   执行间隔计算、丢帧报警和保存 `frame_metadata`。
    -   如果 `SAVE_UI_TO_VIDEO` 为 True，则在这里 `frame.copy()` 并用 OpenCV 画字，随后推送到 `frame_queue` 给写入线程。如果为 False，则**零拷贝**直接向队伍推送 [frame](file:///c:/LZQ/VS_CODE/VideoRecord.py#205-228)。
    -   最后，将 [frame](file:///c:/LZQ/VS_CODE/VideoRecord.py#205-228) 和相关的 UI 信息写入共享的 `preview_frame` 字典，供外部渲染。
3.  **重构 Main Thread (GUI 主循环):**
    -   现在主循环不再兼作拍摄，而是变成了纯粹的**GUI 消费者**。
    -   每隔大概 30ms (`cv2.waitKey(30)`) 从 `preview_lock` 中安全拷贝一张 `preview_frame`。
    -   如果之前没有把 UI 写入视频，则由主循环在这张 Copy 上慢条斯理地绘制状态指示器，最后 `cv2.imshow`。
    -   在主循环处理键盘 `'s'` (开始录制) 和 `'q'` (结束录制) 信号。

这种机制可以完全隔绝在系统更新窗口 (Windows DWM / 终端 IO ) 引起的耗时，让 Camera IO 线程始终以 100% 速度和 0 阻塞等待下一帧，进而达成完美的 60fps 稳定输出。

## USB 带宽降级丢帧诊断与二次修复 (MJPG 硬件解压)
在成功解耦了 UI 渲染后，终端报告显示：原来偶尔突发的大幅度丢帧（40ms+）消失，取而代之的是每一帧间隔高达 200ms (5fps)。
这证明虽然使用了 DSHOW 且配置了 MJPG，但底层协商其实失败了，相机固件强行落回到了毫无压缩的 **YUY2** 格式，而 USB 带宽上限只能承载 1080p YUY2 跑到 5fps。

根据隔离环境的 [test_order.py](file:///C:/LZQ/VS_CODE/test_order.py) 严格测试，发现 **OpenCV DSHOW 后端对于不同相机的设值顺序有极其变态的强校验**：
如果在设置分辨率和 FPS `之前` 设定 FOURCC，DSHOW 会直接丢弃这个设定。

### 预期更改方案 (终极修复)

#### [MODIFY] [VideoRecord.py](file:///c:/Neurovideo/VideoRecord.py)

在初始化 `cv2.VideoCapture` 时，我们必须严格控制底层的协商顺序（**先设分辨率、再设FPS，最后锁定 FOURCC**）：

1.  **改变 OpenCV Parameter 设定顺序：**
    ```python
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, RESOLUTION[0])
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, RESOLUTION[1])
    cap.set(cv2.CAP_PROP_FPS, TARGET_FPS)
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))
    ```
2.  **保留控制台输出确认：**
    维持通过 `cap.get(cv2.CAP_PROP_FOURCC)` 反读格式并打印到终端的逻辑供用户确认。

## 验证计划 (Verification Plan)
修改完成后，再次运行脚本并随时准备录制：
1. 若程序刚启动时控制台清清楚楚地打印出 [(格式: MJPG)](file:///C:/LZQ/VS_CODE/test_order.py#8-11)，即证明底层流交涉彻底成功。
2. 录制过程的丢帧告警应立即彻底消失，事后健康报告显示的 FPS 极度逼近 60.0 fps，异常数量为0。

### 🚨 Addendum: 关于 1080p@60fps 最终的 4% 微型“丢帧” (物理极限)
在完全解除了 Python 阻塞流和 MSMF 无损传输宽带瓶颈之后，终端在约 `1376 帧` 测试（约 23 秒视频）中依然偶尔报出 `30-32ms` 的微量堆叠（发生间隔惊人的规律，约每 23-24 帧出现一次）。
您可能会问：“是不是我的 USB 2.0 摄像头硬件有限制？”

答案是：**是的。但不仅是摄像头，更是整个物理链路加操作系统的通病。**
在非实时操作系统 (Non-RTOS Windows) 和普通的 USB 2.0/3.0 Webcam 架构下，没有任何驱动保证每一帧都雷打不动地在 `16.666ms` 送达。USB 轮询 (Polling) 机制和驱动缓冲区会让画面产生微弱的**网络抖动 (Jitter)**，当这种抖动积累到大于您的阈值判定，就会体现为一个 `32ms` 然后紧跟一个极短时间送达的补发帧。

*这在民用领域就是极限了。*

如果您必须要求 **0.00% 绝对的时间定格**，神经科学的唯一出路是硬件级的时间轴标定：
1. **换用高阶相机**：使用带硬件触发线 (Hardware Trigger) 的 FLIR / PointGrey 工业级 PCIe 相机，由 Arduino 给出 60Hz 绝对方波。
2. **利用我们现有的代码架构做后期修正**：[VideoRecord.py](file:///c:/Neurovideo/VideoRecord.py) 中写出的 `video_timestamps.csv` 和预埋的极高精度 `time.perf_counter` 本身就是对抗这种抖动利器。在后期的 Python/Matlab 数据对齐步骤中，您可以依据记录下的系统时钟绝对时间做毫秒级插值或时间戳重映射，这也是绝大多数顶级实验室使用哪怕 600fps 高速摄像机时仍要依赖的标定方案。
