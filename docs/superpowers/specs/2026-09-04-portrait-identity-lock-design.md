# Portrait Lab R11 本机身份锁定架构设计

日期：2026-09-04
目标设备：Samsung S24U / Android arm64
目标分支：`feat/portrait-mvp`

## 1. 问题定义

当前 R10.1 的 QNN/DMD2 路径把用户照片作为 img2img 初始图，同时用风格 prompt 和 denoise strength 驱动生成。它能稳定改变画风，但没有独立的身份表示、身份注入或身份验收，因此“风格对、脸漂移”是架构必然结果。

R11 的目标不是继续调低 denoise，而是在保留现有 QNN/HTP 风格生成速度的前提下，把“是谁”和“什么风格”拆成两个独立信号，并对最终输出执行本机身份锁定和身份 QA。

成功标准：

1. 保留现有 8 种风格和 QNN/DMD2 主生成路径；
2. 用户照片不上传；
3. QNN 完成后只修改脸部区域，不重算身体、服装、背景和整体风格；
4. 输出前计算源脸与结果脸的 ArcFace cosine similarity；
5. 身份校正后相似度必须显著优于校正前；低于门槛时不得伪装为“生成成功”；
6. 无网络时，已安装身份模型包可完整运行；
7. S24U 真机记录 QNN 生成耗时、身份锁定耗时和 QA 分数。

## 2. 方案比较

### 方案 A：把 PhotoMaker / InstantID / PuLID 直接塞进 QNN 扩散主干

优点：身份条件从扩散阶段就参与采样，理论上最“原生”。

问题：当前 Local Dream QNN 后端使用定制 SDXL/DMD2 模型目录和 QNN/HTP runtime，不是 stable-diffusion.cpp 的标准 SDXL safetensors 路径。PhotoMaker 虽已被新版 stable-diffusion.cpp 支持，但直接接入当前 QNN DMD2 需要重做条件编码、LoRA/adapter 注入和 QNN 图转换，改动大且会显著延长本轮交付。

结论：保留为 R12 原生身份条件路线，不作为 R11 首个锁脸闭环。

### 方案 B：QNN 风格生成 + 本机 Face Identity Lock + ArcFace QA（R11 采用）

流程：

```text
源照片
  ├─ SCRFD/RetinaFace → 5 点关键点 → ArcFace identity embedding
  │
  └─ QNN/DMD2 → 风格结果
                    │
                    ├─ 目标脸检测/对齐
                    ├─ InSwapper identity transfer
                    ├─ 仿射逆变换 + feather mask 贴回
                    └─ ArcFace QA
                          ↓
                       最终图
```

优点：

- 不破坏已经跑通的 QNN/HTP 生成链；
- “风格”仍由 DMD2 负责，“是谁”由独立身份模型负责；
- 只处理脸部 ROI，避免重新生成服装、姿态和背景；
- 可在 Android 本机 ONNX Runtime 后台线程执行；
- 可独立测试每个边界：检测、对齐、embedding、swap、blend、QA。

代价：需要单独的身份模型包；InSwapper/InsightFace 预训练模型存在单独许可要求，因此 R11 研究 APK 不把模型权重提交到公开仓库，模型管理页显示许可说明并按 manifest + SHA-256 下载/校验。

### 方案 C：仅降低 denoise / 固定 seed / 提高参考图权重

这只能减少变化，不能建立身份条件。风格越强，身份仍会漂移。拒绝作为锁脸方案。

## 3. R11 架构

### 3.1 Flutter 层

新增：

- `PortraitIdentityPolicy`
  - `enabled`：默认 true
  - `strength`：默认 0.88
  - `minSimilarity`：默认 0.40
  - `minImprovement`：默认 0.08
- `PortraitGenerationRequest.identityPolicy`
- 新状态：
  - `detectingIdentity`
  - `extractingIdentity`
  - `lockingIdentity`
  - `verifyingIdentity`
  - `identityLockFailed`
- 结果页显示：
  - `source → pre-lock` cosine
  - `source → post-lock` cosine
  - identity lock 耗时
  - 是否通过 QA

主控制器顺序：

```text
QNN generate
  → temporary styled PNG
  → IdentityLockEngine.lock(source, styled, policy)
  → QA pass
  → gallery/history save
```

身份锁失败时不直接覆盖原图并宣称完成。开发版允许展示“风格原图”和失败原因，但正式成功态只接受 QA 通过结果。

### 3.2 Android 原生层

新增 MethodChannel：

`com.qujindai.localportraitlab/identity_lock`

方法：

- `status`
- `prepareModels`
- `analyzeSource`
- `lock`
- `cancel`

所有 ONNX、Socket、文件和图像重采样工作放在专用 executor，禁止运行在 Flutter/UI 主线程。

新增组件：

1. `PortraitIdentityModelPackService`
   - manifest 驱动下载
   - `.part` 原子下载
   - SHA-256 校验
   - 断点/失败状态
   - 不把大模型写入 APK 或 Git

2. `PortraitFaceDetector`
   - SCRFD/RetinaFace ONNX
   - 单人肖像默认选“面积最大 + 接近中心”的脸
   - 输出 bbox + 5 landmarks + confidence

3. `PortraitArcFaceEncoder`
   - 5 点 similarity transform 对齐到 112×112 ArcFace template
   - 生成 512D embedding
   - L2 normalization
   - cosine similarity

4. `PortraitInSwapper`
   - 目标脸按 5 点关键点对齐到 128×128
   - source normalized embedding 乘 InSwapper embedding map 并重新 L2 normalize
   - ONNX Runtime inference
   - 结果反向仿射贴回

5. `PortraitFaceBlend`
   - 根据目标脸大小生成收缩 + 羽化 mask
   - 只在脸部 ROI 混合
   - 不对身体、头发外轮廓和背景做全图 img2img

6. `PortraitIdentityQualityGate`
   - `preSimilarity = cosine(source, preLockTarget)`
   - `postSimilarity = cosine(source, postLockTarget)`
   - 默认通过条件：`postSimilarity >= minSimilarity` 且 `postSimilarity - preSimilarity >= minImprovement`
   - 若 preSimilarity 已经很高（>= minSimilarity），允许 `postSimilarity >= preSimilarity - 0.02`，防止不必要的过度修脸

### 3.3 模型包

R11 不提交第三方权重到仓库。模型包 manifest 至少声明：

```json
{
  "version": 1,
  "files": [
    {"role":"detector","name":"det_10g.onnx","sha256":"...","url":"..."},
    {"role":"recognizer","name":"w600k_r50.onnx","sha256":"...","url":"..."},
    {"role":"swapper","name":"inswapper_128.onnx","sha256":"...","url":"..."}
  ]
}
```

下载源与哈希在实现时锁定到可审计版本。InsightFace 代码可参考 MIT 实现，但其训练数据/预训练模型及 InSwapper 模型有单独许可要求；因此模型管理页必须标注“研究/评估用途，商业使用需单独取得模型许可”，并保留第三方 NOTICE。

## 4. 数据流

```text
P01 选择用户照片
  ↓
本机 detector
  ↓
5 landmarks + source embedding（仅内存/应用私有缓存）
  ↓
P02 选择风格
  ↓
QNN/DMD2 127.0.0.1:8082 本机生成
  ↓
pre-lock PNG
  ↓
目标脸检测 + 对齐
  ↓
InSwapper 强身份校正
  ↓
feather blend
  ↓
ArcFace post-lock embedding
  ↓
Identity QA
  ├─ PASS → 保存最终作品
  └─ FAIL → identityLockFailed，保留诊断，不伪装成功
```

用户照片、embedding 和生成结果均不上传。身份 embedding 默认不写历史库；只存相似度分数和模型 pack 版本，便于复现而不存生物特征正文。

## 5. UI 行为

默认用户不需要理解算法，首页只显示：

- `锁定本人身份`：默认开启
- `锁脸强度`：默认 88%，高级设置可调

生成页真实显示阶段：

1. 分析人物特征
2. QNN 风格生成
3. 锁定本人身份
4. 身份一致性校验
5. 保存

结果页开发信息：

```text
Identity: PASS
pre  0.27
post 0.61
Δ    +0.34
lock 1.8 s
pack insightface-r11-v1
```

不再把“分析人物特征”做成假 UI；没有真实 detector/embedding 回调就不能显示完成。

## 6. 错误处理

- 源图无人脸：生成前阻止，提示重新选择清晰单人照；
- 源图多人脸：默认选中心最大脸，同时在 UI 给出选择提示；
- 结果图无人脸：`identityLockFailed`，不保存为正式成功作品；
- 模型包未安装：进入模型管理下载，不退化成“假锁脸”；
- ONNX OOM：释放 session，报告 identity runtime OOM；QNN 原结果只作为诊断预览；
- 用户取消：同时取消 QNN 请求和 identity executor，禁止进入 completed；
- QA 不通过：返回 pre/post 分数和失败原因，不隐藏重试。

## 7. 测试门禁

### G0 静态/合同测试

- request 中必须存在 `identityPolicy`；
- QNN transport 仍只访问 localhost；
- identity method channel 不能在主线程执行推理；
- APK/仓库不得包含未授权 InsightFace 权重。

### G1 数学单测

- 5 点 similarity transform；
- L2 normalize；
- cosine similarity；
- InSwapper embedding-map multiply；
- inverse affine；
- feather mask 边界。

### G2 Android 单测/契约测试

- method channel 生命周期；
- 模型 manifest SHA 校验；
- 错误映射；
- executor 与主线程隔离。

### G3 Flutter 流程测试

- identity enabled：QNN → lock → QA → save；
- identity disabled：仅作为显式高级调试模式；
- QA fail 不能进入 completed；
- cancel 后不能保存；
- 结果页显示真实 pre/post 分数。

### G4 CI

- `flutter test test/portrait_lab`
- Android Kotlin compile
- arm64 debug APK
- QNN runtime bundle 检查
- identity model weights absence check

### G5 S24U 真机门禁

至少 1 张本人照片 × 3 个差异最大的风格：

- 商务肖像
- 漫画风
- 古风或赛博朋克

每组记录：

- QNN time
- identity lock time
- pre similarity
- post similarity
- total time
- peak memory
- temperature

验收重点不是只看“风格像”，而是三种风格输出都必须通过同一身份 QA。

## 8. 实施边界

R11 本轮做：

- QNN 后处理身份锁定
- ArcFace QA
- 模型包管理
- UI 真实状态和诊断
- S24U 可安装 APK

R11 本轮不做：

- 多人换脸
- 视频逐帧身份一致性
- PhotoMaker/PuLID 直接注入 QNN 图
- 云端推理
- 商业授权模型分发

R12 再评估将 PhotoMaker/PuLID/InstantID 身份条件直接并入扩散主干，以减少后处理痕迹；R11 先建立可测、可验收、不会再“把参考图当锁脸”的真实身份闭环。
