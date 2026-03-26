# CSDS 多模态神经行为学分析管线 (Master 整合终稿)

**文档属性**：标准操作规程 (SOP)、高精度多模态数据同步协议与分析数学蓝图
**适用配置**：基于头件固定 (Head-fixed) 的清醒小鼠、Neuropixels 高通量电生理、Arduino 行为控制、高频面部摄像
**核心范式**：单液体区块扰动设计 (Single-Liquid Acute Perturbation Block Paradigm)

---

## 1. 实验物理设计与范式升维

### 1.1 实验舱物理布局 (Head-fixed Setup)
小鼠通过头件 (Headbar) 与牙科水泥长期固定在实验跑台或限位管中。
*   **面部摄像**：高速摄像头位于小鼠吻部侧方，记录瞳孔、胡须垫、下颌与整体面部的精细运动。
*   **给水/舔舐模块**：Arduino 控制的单路金属水嘴固定在小鼠舌头伸出的极限工作距离内，Touch Sensor (A1) 绑定于此。
*   **光学标记**：宏观事件红外 LED (D7) 并联在 Arduino 上，且必须放置在面部摄像头的**视野边缘**。它的亮起代表了绝对的宏观物理事件（给水/电击）时间点。

### 1.2 范式进化论：为什么放弃范式 1 选择范式 2？

| 维度 | 早期构想 (双水嘴/四水嘴选择) | 本管线 (Head-fixed 单日单液体区块测试) |
| :--- | :--- | :--- |
| **主动性** | 小鼠主动选择（自由决定去左边还是右边） | 系统强迫给予（预期内刺激注入） |
| **数据纯净度** | **低**。受严重的空间位置偏好影响，且如果混合给予不同药液，极易发生“感觉混淆 (Sensory Contrast)”。 | **极高**。一天一根管子一种液体，物理层面上断绝了 100% 的交叉污染。 |
| **科学解答能力** | 只能浅显回答：“这只老鼠总体更喜欢糖还是水？” | 能够深刻测定：“在遭受急性电击后，这只老鼠特定面部特征向量（效价）是否瞬间被抹除了？” |

---

## 2. 实验设计与完整时间线全景图

### 2.1 实验大周期时间轴 (Timeline)
*   **阶段一：环境与舔水建立 (Day -7 到 Day -4)**
    *   **脚本**：运行 `HabituationParadigm.ino`。
    *   **动作**：执行单循环的 50 个随机纯液体 Trial。无电击。
    *   **目的**：头件固定脱敏，消除对金属水嘴的新异性恐惧。
*   **阶段二：情感效价基线构筑 (Day -3 到 Day -1)**
    *   **脚本**：运行正式版 `MultiStimShockParadigm.ino`。
    *   **顺序与科学理据**：**水 (Day-3) $\rightarrow$ 糖水 (Day-2) $\rightarrow$ 奎宁 (Day-1)**。
        *   首日测水定标代谢水平；次日测糖探明快感天花板；末日测奎宁（最容易引发长期负面联结）探明厌恶底线。从易到难，彻底规避跨日心理污染。
*   **阶段三：CSDS 慢性造模 (Day 1 到 Day 11)**
    *   进行 10 天社会击败，第 11 天进行社会交互测试区分易感/韧性组别。
*   **阶段四：表型与神经重测 (Day 12 到 Day 14)**
    *   **完全重复阶段二**，进行造模前后的 Within-Subject 关键比对。

### 2.2 单日 Session 内部时序解构图 (Flowchart)
在阶段二和阶段四的每一天，小鼠将严格经历下述 A-B-A 自动化扰动区块序列：

```mermaid
graph TD
    A[实验员发送 's' 启动] --> B(INITIAL_WAIT: 20秒前置基线期)
    B --> C{Block 1 (基线区): 25次随机给液循环}
    C -->|ITI 随机等待 10-20s| D[PRE_STIM: 刺激前 3s 无动作]
    D --> E((T=0 锚点: 驱动给水电磁阀 200ms))
    E --> F[POST_STIM: 刺激后 5s 观察]
    F --> C
    C -->|25次完整结束| G(WAIT_SHOCK: 中场静默隔离 60s)
    G --> H[SHOCK_PRE: 电击前纯净基线 5s]
    H --> I((T=0 锚点: 触发 0.5mA 电击 500ms))
    I --> J[SHOCK_POST: 极度应激后观察 15s]
    J --> K(WAIT_BLOCK_2: 恢复期静默隔离 60s)
    K --> L{Block 2 (应激打击后区): 25次随机给液循环}
    L --> M((时序逻辑完全同 Block 1))
    M --> N[DONE: 等待'e'指令手动归档]
```

---

## 3. 跨模态数据重采样与脑电时间轴对齐 (Synchronization Calculus)

本管线采用 **TDT 绝对枢纽架构 (TDT Hub Topology)**，将三套异构独立时钟（Neuropixels 30kHz 时钟、Arduino `millis` 毫秒时钟、OpenCV 视频帧时钟）强行锚定同胚。

### 3.1 硬件对齐链路
1.  **神经元发送端**：Neuropixels 探针通过 Pixel Base Station (PC) 持续向 **TDT (C3 引脚)** 发送 TTL 同步脉冲。
2.  **行为事件发送端**：Arduino 在开场(50ms方波)、给水(200ms方波)、给电击(500ms方波)时，向 **TDT (C0 引脚)** 发送脉冲。
3.  **视觉辅助发送端**：Arduino 给水/电击时同步点亮 D7 红外 LED 供摄像头抓取。每次有效 Lick 动作时独立点亮 D44 黄灯（30ms），不发送 TTL 以保持 TDT 通道高信噪比。

### 3.2 离线 Python 对齐数学演算 (Offline Mathematical Alignment)
**Step 1: Neuropixels Spike Time 线性投影**
提取 TDT 记录系统中的 `TDT_C3_times` 与 Neuropixels 自身记录的同步发出时间 `NP_Sync_times`。
进行线性回归：$\text{TDT\_time} = \alpha * \text{NP\_time} + \beta$。利用 $(\alpha, \beta)$ 将所有单个神经元的 `spike_times` 映射为 `aligned_spike_times_TDT`。

**Step 2: 行为语义从串口中的剥离**
提取串口记录中带时间戳的 `STIMULUS_ON` 事件（Arduino_millis），与 TDT 中捕捉到的方波 `TDT_C0_times` 进行最小二乘法配准验证：
计算 $\text{TDT\_time} = \gamma * \text{Arduino\_millis} + \delta$。
得到映射后，将所有存在于串口中但**没有发出 TTL 的舔水事件 (LICK_EVENT)** 批量转换为 TDT 绝对时间系。

**Step 3: OpenCV 视频光强阈值重构**
利用 Python 提取视频中红外 LED 像素光强的激活帧 `Video_LED_ON_frames`。将其与 TDT 记录的 `TDT_C0_times` 宏观事件序列进行时间规整同化，以此推算出每一帧画面对应的绝对 TDT 时钟戳。一切多模态数据在此刻实现纳秒-毫秒级交汇。

---

## 4. 下一步分析管线部署规范 (Data Analysis Methodology)

参照领域标杆 (*Stringer et al., 2019*; *Dolensek et al., 2020*)，在头件固定范式下应直接采取下述分析路线：

### Phase I: 面部行为学运动特征提取 (Facial Kinematics Extraction)
**步骤 1：全景降维提取 —— Facemap 奇异值分解 (首选)**
*   直接运行开源 Facemap 流水线，对 `[STIM_ON] -3s 到 +5s` 的切片运用运动能量奇异值分解 (Motion Energy SVD)。
*   提取第一主成分 (**PC1**) 作为小鼠全局面部肌肉紧张度/痉挛水平（全局唤醒度 Arousal）的核心张量。
*   同时并行其原生的 Pupil Tracker 提取瞳孔直径，因为瞳孔扩张是被急性电击劫持的最典型自主神经表征。

**步骤 2：精细面部重定义 —— DeepLabCut 姿态估计 (备选)**
*   如果在复杂的奎宁或糖水测试中，SVD (全脸运动) 不足以量化“厌恶”与“愉悦”在面部的结构性差异，则启用 DLC。
*   人工标记**四大主锚点**：嘴唇闭合点、鼻尖、折耳轮廓点。训练模型后，直接得出诸如 "Jaw Open Width" 或 "Ear Pinning" 之类的具象连续运动学变量，作为情感效价图谱。

### Phase II: 舔舐微动结构演算 (Lick Microstructure 解析)
将简单的舔水总数分解为：
*   **ILI (Inter-Lick Interval，舔水群内间歇)**：若造模后变长，属于边缘运动障碍功能性受损。
*   **Burst Size (舔舐簇绝对规模)**：单次不中断连续舔舐的液滴数。这是反映 Hedonic Value（享乐欲望）最纯金的参数。CSDS 鼠在电击后对糖水的 Burst Size 切断，是 Anhedonia 的铁证。

### Phase III: 广义线性/混合效应建模 (PSTH & GLM)
在实现 TDT 轴线上全模态对齐之后：
1.  **绘制 PSTH**：找到给水瞬间（T=0），画出 ACC (前扣带回皮层) 或其它目标神经元在 T=0 前后的放电频率直方图。
2.  **神经编码逆解释 (GLM)**：将提取出的面部 `SVD_PC1`、瞳孔变异量、以及当前的 `Burst Size` 都丢进因变量 $Y$ 的集合，用神经元集群的 Firing Rate 作为自变量 $X$ 进行训练拟合。
3.  **最终结论提炼**：寻找并证明造模前后，有哪一群神经元对于“编码面部表情反应”和“编码预期奖赏丧失”的能力发生了不可逆转的重塑。这即是本项目发向顶刊的方法论通行证。
