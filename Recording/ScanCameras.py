"""
摄像头扫描工具
运行此脚本，自动检测所有可用摄像头及其名称，并弹出预览窗口。
"""
import cv2
import subprocess

def list_dshow_devices():
    """用 pygrabber 枚举 DirectShow 摄像头的真实名称和索引（最准确）"""
    try:
        from pygrabber.dshow_graph import FilterGraph
        g = FilterGraph()
        devices = g.get_input_devices()
        return {i: name for i, name in enumerate(devices)}
    except ImportError:
        print("⚠️  未安装 pygrabber，请运行: pip install pygrabber")
        return {}
    except Exception as e:
        print(f"⚠️  枚举 DirectShow 设备失败: {e}")
        return {}

def scan_cameras(max_index=8, dshow_names=None):
    """扫描 0~max_index-1 的摄像头，返回可用列表"""
    available = []
    print(f"正在扫描摄像头索引 0 ~ {max_index - 1}，请稍候...\n")
    for i in range(max_index):
        cap = cv2.VideoCapture(i, cv2.CAP_DSHOW)  # 使用直连底层硬件的 DSHOW 后端
        if cap.isOpened():
            w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            fps = cap.get(cv2.CAP_PROP_FPS)
            name = dshow_names.get(i, "暂无名称") if dshow_names else "暂无名称"
            available.append({"index": i, "cap": cap, "w": w, "h": h, "fps": fps, "name": name})
        else:
            cap.release()
    return available

def main():
    # 1. 用 pygrabber 枚举 DirectShow 设备名称
    dshow_names = list_dshow_devices()
    print("=" * 55)
    print("  DirectShow 摄像头设备（索引 → 名称）：")
    if dshow_names:
        for idx, name in dshow_names.items():
            print(f"    Index {idx}  →  {name}")
    else:
        print("    （未检测到设备，请检查摄像头连接）")
    print("=" * 55 + "\n")

    # 2. 按索引扫描（传入名称对应表）
    cameras = scan_cameras(max_index=8, dshow_names=dshow_names)

    if not cameras:
        print("❌ 未找到任何可用摄像头，请检查连接或驱动。")
        return

    print(f"✅ 共找到 {len(cameras)} 个可用摄像头：")
    for cam in cameras:
        print(f"  Index {cam['index']}  |  {cam['name']}  |  {cam['w']}x{cam['h']} @ {cam['fps']:.0f}fps")
    print()
    print("• 在 VideoRecord.py 配置区修改 CAMERA_INDEX 为对应索引即可。")
    print("• 按 'Q' 关闭预览窗口退出。\n")

    # 3. 开启预览窗口
    while True:
        all_closed = True
        for cam in cameras:
            ret, frame = cam["cap"].read()
            if ret:
                all_closed = False
                label = f"Index {cam['index']} | {cam['name']} | {cam['w']}x{cam['h']}"
                cv2.putText(frame, label, (10, 30),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
                cv2.imshow(f"Index {cam['index']} - {cam['name']}", frame)

        key = cv2.waitKey(1) & 0xFF
        if key == ord('q') or all_closed:
            break

    for cam in cameras:
        cam["cap"].release()
    cv2.destroyAllWindows()
    print("✅ 扫描结束，请将对应索引填入 VideoRecord.py 配置区的 CAMERA_INDEX。")

if __name__ == "__main__":
    main()
