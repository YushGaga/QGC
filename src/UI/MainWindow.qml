/****************************************************************************
 *
 * (c) 2009-2020 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *(文件头版权注释)
 ****************************************************************************/

// ============================================================================
// 【叠加说明】本文件 = QGC 原版 MainWindow.qml（一字未改）
//            + 叠加自定义布局（来自 d:\Qt_work\qml000\Main.qml，见文件末尾）
//
//  嵌套适配点（仅针对自定义代码的适配，QGC 原代码零改动）：
//   1. 原自定义根节点 Window → 改为铺满主窗口的 Item（id 仍叫 gcs，
//      因此自定义代码里所有 gcs.width / gcs.height 引用无需任何改动）
//   2. 删除 Window 专有属性 visible / color / opacity / maximumWidth 等
//   3. 叠加层放在 PlanView 之后：始终盖在 飞行视图/规划视图 之上；
//      打开工具抽屉(toolDrawer)或弹窗(Popup)时会被它们覆盖
//   4. 叠加层不设背景、不加整层 MouseArea → 空白区域点击穿透到地图
//   5. visible: !planView.visible —— 进入航线规划页时隐藏自定义栏，
//      避免遮挡 PlanView 自带顶栏（其含"退出计划"返回按钮）
//   6. 为使自定义组件与 QGC 功能对应，给原按钮补了 onClicked 绑定；
//      所有与 QGC 已有功能重复的地方用 【重复功能】 注释标出
//   7. 原自定义文件中被注释掉的死代码块（旧版 delegate 等约 80 行）已省略，
//      运行逻辑未动
//   8. 图标仍为本地绝对路径 file:///…，后续建议放入 qrc 资源编译进程序
//   9. 自定义所需 import（QtQuick.Layouts / Controls）QGC 原文件已有，无需新增
// ============================================================================

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window

import QGroundControl
import QGroundControl.Palette   ///全局配色主题
import QGroundControl.Controls
import QGroundControl.FactControls    ///参数控件（QGC 的 Fact 是后端参数模型）
import QGroundControl.ScreenTools   ///屏幕、字体尺寸工具（统一字体高度、宽度，适配桌面/平板/手机）
import QGroundControl.FlightDisplay    ///飞行 HUD
import QGroundControl.FlightMap    ///地图组件

import QGroundControl.UTMSP     ///UAS Traffic Management，无人机空域管理、飞行激活、远程ID模块

/// @brief Native QML top level window
/// All properties defined here are visible to all QML pages.
ApplicationWindow {   ///根窗口定义
    id:             mainWindow    ///根窗口对象id，全局所有子QML都可以通过`mainWindow.xxx`访问
    visible:        true

    property bool   _utmspSendActTrigger
    property bool   _utmspStartTelemetry
    ///布尔标记，给UTMSP空域激活模块用，用来触发激活指令下发、遥测开启，后面有Connections给它赋值

    Component.onCompleted: {
        // Start the sequence of first run prompt(s)
        firstRunPromptManager.nextPrompt()   ///这个QML组件加载完成之后自动执行,作用：启动【首次运行引导弹窗队列】，比如第一次打开 QGC 的欢迎提示、协议弹窗等。
    }

    /// Saves main window position and size and re-opens it in the same position and size next time
    MainWindowSavedState {   ///QGC自定义控件，自动保存窗口位置、窗口大小；下次打开自动恢复上次窗口位置尺寸。
        window: mainWindow
    }

    QtObject {   ///`QtObject`：纯逻辑对象，没有界面，只存属性、函数。
        id: firstRunPromptManager   ///首次启动弹窗管理器

        property var currentDialog:     null
        property var rgPromptIds:       QGroundControl.corePlugin.firstRunPromptsToShow()   ///从C++核心插件拿到需要依次弹出的引导弹窗ID列表
        property int nextPromptIdIndex: 0

        function clearNextPromptSignal() {   ///手动断开信号连接，防止程序退出时野指针（QML对象销毁后信号继续触发崩溃）
            if (currentDialog) {
                currentDialog.closed.disconnect(nextPrompt)
            }
        }

        function nextPrompt() {   ///循环逐个创建弹窗、打开弹窗；弹窗关闭后自动调用`nextPrompt()`弹出下一个
            if (nextPromptIdIndex < rgPromptIds.length) {
                var component = Qt.createComponent(QGroundControl.corePlugin.firstRunPromptResource(rgPromptIds[nextPromptIdIndex]));
                currentDialog = component.createObject(mainWindow)
                currentDialog.closed.connect(nextPrompt)
                currentDialog.open()
                nextPromptIdIndex++
            } else {   ///全部弹窗走完之后，调用`showPreFlightChecklistIfNeeded()`：按需弹出起飞前检查清单
                currentDialog = null
                showPreFlightChecklistIfNeeded()
            }
        }
    }

    readonly property real      _topBottomMargins:          ScreenTools.defaultFontPixelHeight * 0.5

    //-------------------------------------------------------------------------
    //-- Global Scope Variables

    QtObject {
        id: globals   ///是全局变量盒子，方便所有页面读取

        readonly property var       activeVehicle:                  QGroundControl.multiVehicleManager.activeVehicle    ///当前选中/连接的无人机（多机管理器multiVehicleManager）
        readonly property real      defaultTextHeight:              ScreenTools.defaultFontPixelHeight
        readonly property real      defaultTextWidth:               ScreenTools.defaultFontPixelWidth
        readonly property var       planMasterControllerFlyView:    flyView.planController   ///(`planController`：任务规划控制器)
        readonly property var       guidedControllerFlyView:        flyView.guidedController   ///(`guidedController`：定点引导模式控制器)

        // Number of QGCTextField's with validation errors. Used to prevent closing panels with validation errors.
        property int                validationErrorCount:           0    ///核心作用：如果有输入框校验失败，禁止切换页面、关闭面板(`validationErrorCount`：表单校验错误计数)

        // Property to manage RemoteID quick access to settings page
        property bool               commingFromRIDIndicator:        false   ///`commingFromRIDIndicator`：标记是不是从RemoteID（远程ID）指示器跳转进设置页
    }

    /// Default color palette used throughout the UI
    QGCPalette { id: qgcPal; colorGroupEnabled: true }   ///全局调色板，QGC统一主题颜色，所有界面取`qgcPal.xxx`

    //-------------------------------------------------------------------------
    //-- Actions

    ///全局信号定义
    signal armVehicleRequest   ///上锁
    signal forceArmVehicleRequest   ///强制上锁
    signal disarmVehicleRequest   ///解锁
    signal vtolTransitionToFwdFlightRequest   ///VTOL垂起机切换：向前飞行模式
    signal vtolTransitionToMRFlightRequest   ///VTOL垂起机切换：多旋翼模式
    signal showPreFlightChecklistIfNeeded   ///触发前检查清单弹窗

    //-------------------------------------------------------------------------
    //-- Global Scope Functions

    // This function is used to prevent view switching if there are validation errors
    ///全局工具函数
    function allowViewSwitch(previousValidationErrorCount = 0) {
        /*`allowViewSwitch()`：页面切换保护函数; 到处都会调用它：切页面、打开抽屉、关闭抽屉前先判断能不能切
        **逻辑：1.如果当前焦点在参数输入框，主动触发编辑完成、执行校验; 2.如果校验错误数量没有新增，返回true，允许切换；否则禁止切换，防止带错误表单跳转 */
        // Run validation on active focus control to ensure it is valid before switching views
        if (mainWindow.activeFocusControl instanceof FactTextField) {
            mainWindow.activeFocusControl._onEditingFinished()
        }
        return globals.validationErrorCount <= previousValidationErrorCount   ///全局对象`globals.validationErrorCount`记录表单错误数量，是`allowViewSwitch`判断依据。
    }

    ///两个主视图切换：飞行视图 ↔ 任务规划视图。(planView:任务规划视图; flyView:飞行视图)
    function showPlanView() {
        ///切到飞行画面：flyView显示，规划画面隐藏
        flyView.visible = false
        planView.visible = true
    }

    function showFlyView() {
        ///切到任务规划画面：规划画面显示，飞行画面隐藏
        flyView.visible = true
        planView.visible = false
    }

    /*- 根据当前是飞行页/规划页，设置返回图标
    **- 加载对应的QML页面到抽屉里，显示抽屉 */
    ///点击菜单打开的右侧滑出大面板
    function showTool(toolTitle, toolSource, toolIcon) {   ///`showTool()`：打开【侧边工具抽屉（toolDrawer）】的通用封装函数
        toolDrawer.backIcon     = flyView.visible ? "/qmlimages/PaperPlane.svg" : "/qmlimages/Plan.svg"
        toolDrawer.toolTitle    = toolTitle
        toolDrawer.toolSource   = toolSource
        toolDrawer.toolIcon     = toolIcon
        toolDrawer.visible      = true
    }

    /*基于 `showTool` 封装好的快捷入口：
    **- 日志分析工具
    **- 飞控配置页面
    **- 直接跳到参数页、跳到指定组件配置页
    **- 应用设置，支持直接跳转到设置里某个子页面 */
    function showAnalyzeTool() {   ///打开日志分析工具页面
        showTool(qsTr("Analyze Tools"), "qrc:/qml/QGroundControl/AnalyzeView/AnalyzeView.qml", "/qmlimages/Analyze.svg")
    }

    function showVehicleConfig() {   ///打开飞控配置主页面
        showTool(qsTr("Vehicle Configuration"), "qrc:/qml/QGroundControl/VehicleSetup/SetupView.qml", "/qmlimages/Gears.svg")
    }

    function showVehicleConfigParametersPage() {   ///打开飞控配置页面，并直接跳转【参数面板】
        showVehicleConfig()
        toolDrawerLoader.item.showParametersPanel()
    }

    function showKnownVehicleComponentConfigPage(knownVehicleComponent) {   ///打开飞控配置页面，并跳转至指定组件的配置面板
        showVehicleConfig()
        let vehicleComponent = globals.activeVehicle.autopilotPlugin.findKnownVehicleComponent(knownVehicleComponent)
        if (vehicleComponent) {
            toolDrawerLoader.item.showVehicleComponentPanel(vehicleComponent)
        }
    }

    function showSettingsTool(settingsPage = "") {   ///打开应用设置页面，可传入参数直接跳转到设置内指定子页面
        showTool(qsTr("Application Settings"), "qrc:/qml/QGroundControl/Controls/AppSettings.qml", "/res/QGCLogoWhite")
        if (settingsPage !== "") {
            toolDrawerLoader.item.showSettingsPage(settingsPage)
        }
    }

    //-------------------------------------------------------------------------
    //-- Global simple message dialog
    ///('showMessageDialog'通用消息弹窗封装;)封装通用弹窗，给全程序调用；`_showMessageDialog`专供 C++侧 `QGCApplication`调用。
    function showMessageDialog(dialogTitle, dialogText, buttons = Dialog.Ok, acceptFunction = null, closeFunction = null) {
        simpleMessageDialogComponent.createObject(mainWindow, { title: dialogTitle, text: dialogText, buttons: buttons, acceptFunction: acceptFunction, closeFunction: closeFunction }).open()
    }

    // This variant is only meant to be called by QGCApplication
    function _showMessageDialog(dialogTitle, dialogText) {
        showMessageDialog(dialogTitle, dialogText)
    }

    Component {
        id: simpleMessageDialogComponent

        QGCSimpleMessageDialog {
        }
    }

    ///程序退出检查逻辑
    property bool _forceClose: false

    function finishCloseProcess() {   ///`finishCloseProcess()`：真正执行退出流程
        _forceClose = true
        // For some reason on the Qml side Qt doesn't automatically disconnect a signal when an object is destroyed.
        // So we have to do it ourselves otherwise the signal flows through on app shutdown to an object which no longer exists.
        firstRunPromptManager.clearNextPromptSignal()   ///标记强制关闭
        QGroundControl.linkManager.shutdown()   ///清理弹窗信号连接
        QGroundControl.videoManager.stopVideo();   ///关闭通信链路管理器、停止视频流
        mainWindow.close()   ///关闭窗口
    }

    // Check for things which should prevent the app from closing
    //  Returns true if it is OK to close
    ///掩码标记，控制跳过哪一项退出检查：
    readonly property int _skipUnsavedMissionCheckMask: 0x01   ///跳过未保存任务检查
    readonly property int _skipPendingParameterWritesCheckMask: 0x02   ///跳过正在写入参数检查
    readonly property int _skipActiveConnectionsCheckMask: 0x04   ///跳过还有无人机连接检查
    property int _closeChecksToSkip: 0
    function performCloseChecks() {   ///'performCloseChecks()':依次执行三项检查，任意一项不通过就返回 false，阻止关闭。
        if (!(_closeChecksToSkip & _skipUnsavedMissionCheckMask) && !checkForUnsavedMission()) {
            return false
        }
        if (!(_closeChecksToSkip & _skipPendingParameterWritesCheckMask) && !checkForPendingParameterWrites()) {
            return false
        }
        if (!(_closeChecksToSkip & _skipActiveConnectionsCheckMask) && !checkForActiveConnections()) {
            return false
        }
        finishCloseProcess()
        return true
    }

    property string closeDialogTitle: qsTr("Close %1").arg(QGroundControl.appName)

    ///下面三个`checkXXX`函数分别实现检查逻辑，检查不通过就弹出Yes/No弹窗：
    function checkForUnsavedMission() {   ///`checkForUnsavedMission()`：任务有没有修改没保存，关闭会丢航点任务
        if (planView._planMasterController.dirty) {
            showMessageDialog(closeDialogTitle,
                              qsTr("You have a mission edit in progress which has not been saved/sent. If you close you will lose changes. Are you sure you want to close?"),
                              Dialog.Yes | Dialog.No,
                              function() { _closeChecksToSkip |= _skipUnsavedMissionCheckMask; performCloseChecks() })
            return false
        } else {
            return true
        }
    }

    function checkForPendingParameterWrites() {   ///`checkForPendingParameterWrites()`：有没有参数正在往飞控刷写，关闭会参数写入失败
        for (var index=0; index<QGroundControl.multiVehicleManager.vehicles.count; index++) {
            if (QGroundControl.multiVehicleManager.vehicles.get(index).parameterManager.pendingWrites) {
                mainWindow.showMessageDialog(closeDialogTitle,
                    qsTr("You have pending parameter updates to a vehicle. If you close you will lose changes. Are you sure you want to close?"),
                    Dialog.Yes | Dialog.No,
                    function() { _closeChecksToSkip |= _skipPendingParameterWritesCheckMask; performCloseChecks() })
                return false
            }
        }
        return true
    }

    function checkForActiveConnections() {   ///`checkForActiveConnections()`：还有无人机在线连接，确认是否退出
        if (QGroundControl.multiVehicleManager.activeVehicle) {
            mainWindow.showMessageDialog(closeDialogTitle,
                qsTr("There are still active connections to vehicles. Are you sure you want to exit?"),
                Dialog.Yes | Dialog.No,
                function() { _closeChecksToSkip |= _skipActiveConnectionsCheckMask; performCloseChecks() })
            return false
        } else {
            return true
        }
    }

    ///窗口关闭事件回调：窗口点叉时触发，调用退出检查；如果检查不通过，`close.accepted=false`，阻止窗口关闭。
    onClosing: (close) => {
        if (!_forceClose) {
            _closeChecksToSkip = 0
            close.accepted = performCloseChecks()
        }
    }

    ///背景、两大主视图
    background: Rectangle {
        anchors.fill:   parent
        color:          QGroundControl.globalPalette.window
    }

    FlyView {   ///飞行主界面（地图、HUD、摇杆、状态），默认显示；把`_utmspSendActTrigger`传给 FlyView，用于UTMSP激活交互
        id:                     flyView
        anchors.fill:           parent
        utmspSendActTrigger:    _utmspSendActTrigger
    }

    PlanView {   ///任务规划界面（航点编辑、航线），默认隐藏，调用`showPlanView()`才显示
        id:             planView
        anchors.fill:   parent
        visible:        false
    }

// ============================================================================
// ===================【自定义布局叠加层 开始】=================================
// == 来源：d:\Qt_work\qml000\Main.qml（原根节点 Window → Item，其余逻辑未动）==
// == 层级：盖在 flyView / planView 之上，被 toolDrawer / 各 Popup 覆盖      ==
// ============================================================================
    Item {
        id: gcs
        anchors.fill: parent
        visible: !planView.visible   // 适配点5：规划页有自己的顶栏，进入时隐藏自定义栏

    //状态标记变量
        property bool showToolbar1: true
        property bool showToolbar2: true

        property bool allChecked: {
            // 计算属性：遍历model，判断是否全部选中
            let allSel = true
            for(let i=0; i<droneModel.count; i++){
                if(!droneModel.get(i).selected){
                    allSel = false
                    break
                }
            }
            return allSel
        }

//顶部导引栏
        Rectangle{
            id:topdaohanglan
            anchors.left:parent.left
            anchors.right:parent.right
            anchors.top:parent.top
            height: gcs.width/25
            width: gcs.width
            color: "blue"
            opacity: 0.7
            visible: true

        //“地面站管理平台”图标+标题
            Rectangle{
                anchors.left:topdaohanglan.left
                anchors.leftMargin: 2
                anchors.verticalCenter:  topdaohanglan.verticalCenter
                height: topdaohanglan.height*0.7
                width: topdaohanglan.width/8
                color: "transparent"
                RowLayout{
                    anchors.centerIn: parent
                    id:tubiao
                    spacing: 5
                    Image {
                        id: gcsImage
                        source: "file:///D:/Qt_work/qml000/icon/gcs.svg"
                        Layout.alignment: Qt.AlignVCenter
                        fillMode: Image.PreserveAspectFit
                                Layout.preferredWidth:tubiao.width*0.3
                                Layout.preferredHeight:tubiao.width*0.3
                                clip:true
                    }
                    Text {
                        id: biaoti
                        text: qsTr("地面站管理平台")
                        color:"white"
                        font.pixelSize: 18
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }
            }

        //5个界面的切界按键
            RowLayout{
                id:qieye
                x:gcs.width*0.2
                width: gcs.width*0.5
                anchors.verticalCenter: topdaohanglan.verticalCenter
                Button{
                    id:dimianzhanpeizhi
                    checkable: true
                    autoExclusive: true
                    contentItem:Item{
                        anchors.fill: parent
                        RowLayout{
                            anchors.centerIn: parent
                            Image{
                                source: "file:///D:/Qt_work/qml000/icon/ground.svg"
                                fillMode: Image.PreserveAspectFit
                                Layout.preferredWidth:dimianzhanpeizhi.width*0.15
                                Layout.preferredHeight:dimianzhanpeizhi.width*0.15
                                clip:true
                            }
                            Text{
                                Layout.fillWidth: true
                                text: "地面站配置"
                                color: "white"
                                font.bold: true
                                font.pixelSize:15
                                elide: Text.ElideRight
                            }
                        }
                    }
                    background: Rectangle{
                        anchors.fill: parent
                        color:dimianzhanpeizhi.clicked? "white":"transparent"
                        opacity: dimianzhanpeizhi.hovered?0.5:0
                    }
                    Layout.fillWidth: true
                    // ====================================================
                    // 【重复功能】QGC 原有入口：主菜单 "Application Settings"
                    // （toolSelectComponent 里的 settingsButton）
                    // ====================================================
                    onClicked: {
                        if (mainWindow.allowViewSwitch()) {
                            mainWindow.showSettingsTool()
                        }
                    }
                }
                Button{
                    id:wurenjipeizhi
                    checkable: true
                    autoExclusive: true
                    contentItem:Item{
                        anchors.fill: parent
                        RowLayout{
                            anchors.centerIn: parent
                            Image{
                                source: "file:///D:/Qt_work/qml000/icon/UAS.svg"
                                fillMode: Image.PreserveAspectFit
                                Layout.preferredWidth:wurenjipeizhi.width*0.15
                                Layout.preferredHeight:wurenjipeizhi.width*0.15
                                clip:true
                            }
                            Text{
                                Layout.fillWidth: true
                                text: "无人机配置"
                                color: "white"
                                font.bold: true
                                font.pixelSize:15
                                elide: Text.ElideRight
                            }
                        }
                    }
                    background: Rectangle{
                        anchors.fill: parent
                        color:wurenjipeizhi.clicked? "white":"transparent"
                        opacity: wurenjipeizhi.hovered?0.5:0
                    }
                    Layout.fillWidth: true
                    // ====================================================
                    // 【重复功能】QGC 原有入口：主菜单 "Vehicle Configuration"
                    // （toolSelectComponent 里的 setupButton）
                    // ====================================================
                    onClicked: {
                        if (mainWindow.allowViewSwitch()) {
                            mainWindow.showVehicleConfig()
                        }
                    }
                }
                Button{
                    id:hangxianguihua
                    checkable: true
                    autoExclusive: true
                    contentItem:Item{
                        anchors.fill: parent
                        RowLayout{
                            anchors.centerIn: parent
                            Image{
                                source: "file:///D:/Qt_work/qml000/icon/hangxianguihua.svg"
                                fillMode: Image.PreserveAspectFit
                                Layout.preferredWidth:hangxianguihua.width*0.2
                                Layout.preferredHeight:hangxianguihua.width*0.2
                                clip:true
                            }
                            Text{
                                Layout.fillWidth: true
                                text: "航线规划"
                                color: "white"
                                font.bold: true
                                font.pixelSize:15
                                elide: Text.ElideRight
                            }
                        }
                    }
                    background: Rectangle{
                        anchors.fill: parent
                        color:hangxianguihua.clicked? "white":"transparent"
                        opacity: hangxianguihua.hovered?0.5:0
                    }
                    Layout.fillWidth: true
                    // ====================================================
                    // 【重复功能】QGC 原有入口：主菜单 "Plan Flight"
                    // （toolSelectComponent 里 SubMenuButton 的 showPlanView()）
                    // 点击后本叠加层自动隐藏（visible: !planView.visible），
                    // 由 PlanView 自带顶栏的"退出计划"按钮返回飞行视图
                    // ====================================================
                    onClicked: {
                        if (mainWindow.allowViewSwitch()) {
                            mainWindow.showPlanView()
                        }
                    }
                }
                Button{
                    id:feiqianyanzheng
                    checkable: true
                    autoExclusive: true
                    contentItem:Item{
                        anchors.fill: parent
                        RowLayout{
                            anchors.centerIn: parent
                            Image{
                                source: "file:///D:/Qt_work/qml000/icon/yanzheng.svg"
                                fillMode: Image.PreserveAspectFit
                                Layout.preferredWidth:feiqianyanzheng.width*0.15
                                Layout.preferredHeight:feiqianyanzheng.width*0.15
                                clip:true
                            }
                            Text{
                                Layout.fillWidth: true
                                text: "飞前验证"
                                color: "white"
                                font.bold: true
                                font.pixelSize:15
                                elide: Text.ElideRight
                            }
                        }
                    }
                    background: Rectangle{
                        anchors.fill: parent
                        color:feiqianyanzheng.clicked? "white":"transparent"
                        opacity: feiqianyanzheng.hovered?0.5:0
                    }
                    Layout.fillWidth: true
                    // ====================================================
                    // 【对应功能】QGC 原有：飞前检查清单弹窗
                    // （signal showPreFlightChecklistIfNeeded，启动引导队列
                    // firstRunPromptManager 走完后触发的就是它）
                    // ====================================================
                    onClicked: {
                        mainWindow.showPreFlightChecklistIfNeeded()
                    }
                }
                Button{
                    id:fenxigongju
                    checkable: true
                    autoExclusive: true
                    contentItem:Item{
                        anchors.fill: parent
                        RowLayout{
                            anchors.centerIn: parent
                            Image{
                                source: "file:///D:/Qt_work/qml000/icon/fenxi.svg"
                                fillMode: Image.PreserveAspectFit
                                Layout.preferredWidth:fenxigongju.width*0.15
                                Layout.preferredHeight:fenxigongju.width*0.15
                                clip:true
                            }
                            Text{
                                Layout.fillWidth: true
                                text: "分析工具"
                                color: "white"
                                font.bold: true
                                font.pixelSize:15
                                elide: Text.ElideRight
                            }
                        }
                    }
                    background: Rectangle{
                        anchors.fill: parent
                        color:fenxigongju.clicked? "white":"transparent"
                        opacity: fenxigongju.hovered?0.5:0
                    }
                    Layout.fillWidth: true
                    // ====================================================
                    // 【重复功能】QGC 原有入口：主菜单 "Analyze Tools"
                    // （toolSelectComponent 里的 analyzeButton，
                    //  QGC 中仅高级模式 showAdvancedUI=true 时可见，
                    //  自定义布局把它固定常显，属功能重复）
                    // ====================================================
                    onClicked: {
                        if (mainWindow.allowViewSwitch()) {
                            mainWindow.showAnalyzeTool()
                        }
                    }
                }
            }

        //4个功能设置
            RowLayout{
                x:gcs.width*0.75
                width: gcs.width*0.15
                anchors.verticalCenter: topdaohanglan.verticalCenter
                Button{
                    id:cion1
                    checkable: true
                    autoExclusive: true
                    icon.source: "file:///D:/GCS LOGE/svg/cion1lingdang.svg"
                    icon.color: "white"
                    background: Rectangle{
                        anchors.fill: parent
                        color:cion1.clicked? "white":"transparent"
                        opacity: cion1.hovered?0.5:0
                    }
                    Layout.fillWidth: true
                    // ====================================================
                    // 【重复功能】通知/告警入口 ≈ QGC 飞行视图顶部告警指示器
                    // + criticalVehicleMessagePopup（严重告警弹窗）
                    // 待接入：可在此调用 mainWindow.showIndicatorDrawer(...)
                    // 打开消息列表指示器
                    // ====================================================
                }
                Button{
                    id:cion2
                    checkable: true
                    autoExclusive: true
                    icon.source: "file:///D:/GCS LOGE/svg/cion2weixing.svg"
                    icon.color: "white"
                    background: Rectangle{
                        anchors.fill: parent
                        color:cion2.clicked? "white":"transparent"
                        opacity: cion2.hovered?0.5:0
                    }
                    Layout.fillWidth: true
                    // ====================================================
                    // 【重复功能】GPS/卫星状态 ≈ QGC FlyView 内置 GPS 卫星
                    // 状态指示器（点击弹出卫星数/信号质量面板）
                    // ====================================================
                }
                Button{
                    id:cion3
                    checkable: true
                    autoExclusive: true
                    icon.source: "file:///D:/GCS LOGE/svg/cion3hangxian.svg"
                    icon.color: "white"
                    background: Rectangle{
                        anchors.fill: parent
                        color:cion3.clicked? "white":"transparent"
                        opacity: cion3.hovered?0.5:0
                    }
                    Layout.fillWidth: true
                    // ====================================================
                    // 【重复功能】航线/任务状态 ≈ QGC FlyView 任务状态指示器
                    // 及上方"航线规划"切界按键（功能重复）
                    // ====================================================
                }
                Button{
                    id:cion4
                    checkable: true
                    autoExclusive: true
                    icon.source: "file:///D:/GCS LOGE/svg/cion4jilu.svg"
                    icon.color: "white"
                    background: Rectangle{
                        anchors.fill: parent
                        color:cion4.clicked? "white":"transparent"
                        opacity: cion4.hovered?0.5:0
                    }
                    Layout.fillWidth: true
                    // ====================================================
                    // 【重复功能】日志记录 ≈ QGC 日志下载（Log Download，
                    // Analyze Tools 内）+ 飞行日志(.tlog/.ulog)自动记录机制
                    // ====================================================
                }
            }
        //退出程序按钮
            Button{
                id: closeCX
                anchors.right:topdaohanglan.right
                anchors.verticalCenter: topdaohanglan.verticalCenter
                height: topdaohanglan.height*0.5
                width: topdaohanglan.width*0.07
                checkable: true
                contentItem:Item{
                    anchors.fill: parent
                    RowLayout{
                        anchors.centerIn: parent
                        Image{
                            source: "file:///D:/Qt_work/qml000/icon/guanji.svg"
                            fillMode: Image.PreserveAspectFit
                            Layout.preferredWidth:closeCX.width*0.2
                            Layout.preferredHeight:closeCX.width*0.2
                            clip:true
                        }
                        Text{
                            Layout.fillWidth: true
                            text: "关闭程序"
                            color: "white"
                            font.pixelSize: 15
                            font.bold: true
                        }
                    }
                }
                background: Rectangle{
                    anchors.fill: parent
                    color:closeCX.clicked? "white":"transparent"
                    opacity: closeCX.hovered?0.5:0
                }
                // ============================================================
                // 【重复功能】QGC 原有关闭入口：
                //  - toolSelectComponent 里 closeButton（仅全屏模式显示）
                //  - 窗口点叉触发的 onClosing 退出检查流程
                // 这里复用 QGC 的 performCloseChecks()：任务未保存/参数写入中/
                // 有连接时弹确认框，全部通过才 finishCloseProcess()
                // ============================================================
                onClicked: {
                    mainWindow.performCloseChecks()
                }
            }
        }

//定位按键
        Button{
            id:dingwei
            anchors.top: topdaohanglan.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: gcs.width*0.025
            height: dingwei.width
            checkable: true
            icon.source: "file:///D:/GCS LOGE/svg/dingwei.svg"
            background: Rectangle{
                anchors.fill: parent
                color:{
                    if (dingwei.pressed) {
                        return "white"
                    }
                    else if (dingwei.hovered) {
                        return "blue"
                    }
                    else {
                        return "blue"
                    }
                }
                opacity: {
                    if (dingwei.pressed) {
                        return 0.5
                    }else if(dingwei.hovered){
                        return 0.5
                    }else{
                        return 0.7
                    }
                }
            }
            // ================================================================
            // 【重复功能】地图定位/回中 ≈ QGC FlyView 地图上的"回中载具"
            // 按钮；载具当前位置 = globals.activeVehicle.coordinate
            // （QGC 无可直接调用的回中函数，如需完全复刻可在 FlyView 内接入）
            // ================================================================
        }

//上方左侧显示栏
    //位置显示
        RowLayout{
            id:zuo
            anchors.top: topdaohanglan.bottom
            anchors.topMargin: 13
            anchors.right: dingwei.left
            anchors.rightMargin: 25
            spacing: 15
            Rectangle{
                id:zuo1
                width: 100
                height: 25
                color: "blue"
                opacity: 0.5
                border.width: 2
                border.color: "cyan"
                Text {
                    id: zuoone
                    // ====================================================
                    // 【重复功能】经度显示 ≈ QGC FlyView 仪表数值行
                    // (HorizontalFactValueGrid / InstrumentValueArea) 的
                    // longitude 项；数据源：载具坐标 activeVehicle.coordinate
                    // ====================================================
                    text: qsTr("目标经度：") + (globals.activeVehicle ? globals.activeVehicle.coordinate.longitude.toFixed(6) : "----")
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 5
                }
            }
            Rectangle{
                id:zuo2
                width: 100
                height: 25
                color: "blue"
                opacity: 0.5
                border.width: 2
                border.color: "cyan"
                Text {
                    id: zuotow
                    // ====================================================
                    // 【重复功能】纬度显示 ≈ QGC FlyView 仪表数值行 latitude 项
                    // ====================================================
                    text: qsTr("目标维度：") + (globals.activeVehicle ? globals.activeVehicle.coordinate.latitude.toFixed(6) : "----")
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 5
                }
            }
            Rectangle{
                id:zuo3
                width: 100
                height: 25
                color: "blue"
                opacity: 0.5
                border.width: 2
                border.color: "cyan"
                Text {
                    id: zuothird
                    // ====================================================
                    // 【重复功能】高度显示 ≈ QGC FlyView 仪表数值行
                    // altitudeRelative（相对高度）项
                    // ====================================================
                    text: qsTr("目标高度：") + (globals.activeVehicle ? globals.activeVehicle.altitudeRelative.rawValue.toFixed(1) + " m" : "----")
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 5
                }
            }
        }

    //速度显示
        RowLayout{
            id:you
            anchors.top: topdaohanglan.bottom
            anchors.topMargin: 13
            anchors.left: dingwei.right
            anchors.leftMargin: 25
            spacing: 15
            Rectangle{
                id:you1
                width: 100
                height: 25
                color: "blue"
                opacity: 0.5
                border.width: 2
               border.color: "cyan"
                Text {
                    id: youone
                    // ====================================================
                    // 【重复功能】俯仰角速度 ≈ QGC FlyView 姿态仪
                    // (VehicleAttitudeWidget) 的姿态数据 roll/pitch/yaw
                    // 字段名以 Vehicle 实际 fact 为准（pitchRate），无数据显示"--"
                    // ====================================================
                    text: qsTr("俯仰角速度：") + (globals.activeVehicle && globals.activeVehicle.pitchRate ? globals.activeVehicle.pitchRate.rawValue.toFixed(2) + " °/s" : "--")
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 5
                }
            }
            Rectangle{
                id:you2
                width: 100
                height: 25
                color: "blue"
                opacity: 0.5
                border.width: 2
                border.color: "cyan"
                Text {
                    id: youtow
                    // 【重复功能】滚转角速度 ≈ QGC 姿态仪数据（rollRate）
                    text: qsTr("滚转角速度：") + (globals.activeVehicle && globals.activeVehicle.rollRate ? globals.activeVehicle.rollRate.rawValue.toFixed(2) + " °/s" : "--")
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 5
                }
            }
            Rectangle{
                id:you3
                width: 100
                height: 25
                color: "blue"
                opacity: 0.5
                border.width: 2
               border.color: "cyan"
                Text {
                    id: youthird
                    // 【重复功能】方位角速度 ≈ QGC 姿态仪/罗盘航向数据（yawRate）
                    text: qsTr("方位角速度：") + (globals.activeVehicle && globals.activeVehicle.yawRate ? globals.activeVehicle.yawRate.rawValue.toFixed(2) + " °/s" : "--")
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 5
                }
            }
        }

//左侧工具栏
    //3个功能按键
        ColumnLayout{
            id:lefttool
            width: parent.width/30
            height: parent.height*0.3
            anchors.left: parent.left
            y:parent.height*0.3
            visible: showToolbar1  // 绑定显示状态
            //滑入滑出效果
            Behavior on x {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            x: showToolbar1 ? 0 : -lefttool.width  // 移出屏幕实现隐藏
            Button{
                id:lefttool1
                checkable: true
                autoExclusive: true
                contentItem:Item{
                    anchors.fill: parent
                    ColumnLayout{
                        anchors.centerIn: parent
                        Image{
                            source: "file:///D:/Qt_work/qml000/icon/jiangluosan.svg"
                            fillMode: Image.PreserveAspectFit
                            Layout.preferredWidth:lefttool1.width*0.6
                            Layout.preferredHeight:lefttool1.width*0.6
                            clip:true
                        }
                        Text{
                            Layout.fillWidth: true
                            text: "不起飞 \n 开伞"
                            color: "white"
                        }
                    }
                }
                background: Rectangle{
                    anchors.fill: parent
                    color:lefttool1.pressed ? "white":"blue"
                    opacity: lefttool1.hovered?0.5:0.7
                }
                Layout.fillWidth: true
                Layout.fillHeight: true
                // ============================================================
                // 【自定义功能】开伞：QGC 无对应功能。
                // 建议接入方式：QGC 的 MavlinkAction（参数页可配自定义
                // MAVLink 指令）或 Vehicle::sendMavCommand 下发开伞指令
                // ============================================================
            }
            Button{
                id:lefttool2
                checkable: true
                autoExclusive: true
                contentItem:Item{
                    anchors.fill: parent
                    ColumnLayout{
                        anchors.centerIn: parent
                        Image{
                            source: "file:///D:/Qt_work/qml000/icon/guanji.svg"
                            fillMode: Image.PreserveAspectFit
                            Layout.preferredWidth:lefttool2.width*0.6
                            Layout.preferredHeight:lefttool2.width*0.6
                            clip:true
                        }
                        Text{
                            Layout.fillWidth: true
                            text: "只关机 \n不开伞"
                            color: "white"
                        }
                    }
                }
                background: Rectangle{
                    anchors.fill: parent
                    color:lefttool2.pressed ? "white":"blue"
                    opacity: lefttool2.hovered?0.5:0.7
                }
                Layout.fillWidth: true
                Layout.fillHeight: true
                // ============================================================
                // 【重复功能】"关机" ≈ QGC 解锁/电机停转 actionDisarm
                // （FlyView 右上角面板 Disarm 按钮、signal disarmVehicleRequest）
                // 走 QGC confirmAction 会先弹出 QGC 自带确认滑块/对话框
                // ============================================================
                onClicked: {
                    var gc = globals.guidedControllerFlyView
                    gc.confirmAction(gc.actionDisarm)
                }
            }
            Button{
                id:lefttool3
                checkable: true
                autoExclusive: true
                contentItem:Item{
                    anchors.fill: parent
                    ColumnLayout{
                        anchors.centerIn: parent
                        Image{
                            source: "file:///D:/Qt_work/qml000/icon/ceju.svg"
                            fillMode: Image.PreserveAspectFit
                            Layout.preferredWidth:lefttool3.width*0.6
                            Layout.preferredHeight:lefttool3.width*0.6
                            clip:true
                        }
                        Text{
                            Layout.fillWidth: true
                            text: "测距"
                            color: "white"
                        }
                    }
                }
                background: Rectangle{
                    anchors.fill: parent
                    color:lefttool3.pressed ? "white":"blue"
                    opacity: lefttool3.hovered?0.5:0.7
                }
                Layout.fillWidth: true
                Layout.fillHeight: true
                // ============================================================
                // 【重复功能】测距 ≈ QGC 地图测距工具/地图比例尺
                // (FlyViewMap 点击测量、MapScale)
                // ============================================================
            }

        }

    //左侧工具栏展示/收回按钮
        Button{
            id:button1
            width: lefttool.width/2
            height: lefttool.width/2
            anchors.verticalCenter:lefttool.verticalCenter
            x: lefttool.visible?lefttool.x + lefttool.width:0
            Behavior on x {
                NumberAnimation { duration:200; easing.type: Easing.OutCubic }
            }
            checkable: true
            icon.source: "file:///D:/Qt_work/qml000/icon/leftarrow1.svg"
            background: Rectangle{
                anchors.fill: parent
                color:{
                    if (button1.pressed) {
                        return "white"
                    }
                    else if (button1.hovered) {
                        return "blue"
                    }
                    else {
                        return "blue"
                    }
                }
                opacity: {
                    if (button1.pressed) {
                        return 0.5
                    }else if(button1.hovered){
                        return 0.5
                    }else{
                        return 0.7
                    }
                }
            }
            onClicked: {
                console.log("click")
                showToolbar1 = !showToolbar1; // 点击取反，切换显示隐藏
            }
        }

//右侧显示栏
        Rectangle{
            id:rightToolbarcol
            width: gcs.width / 5
            height: gcs.height / 1.7
            anchors.right:parent.right
            anchors.margins: 25
            anchors.verticalCenter: button2.verticalCenter
            color:"slategray"
//            opacity: 0.3
            border.width: 1.5
            border.color: "blue"
            visible: showToolbar2  // 绑定显示状态
            //滑入滑出效果（配合）
            Behavior on x {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            x: showToolbar2 ? 0 : -rightToolbarcol.width  // 移出屏幕实现隐藏

            // ============================================================
            // 【重复功能】多机列表面板 ≈ QGC 多机管理：
            //  - 数据源：QGroundControl.multiVehicleManager.vehicles
            //    （QmlObjectListModel，每架无人机一个 Vehicle 对象）
            //  - QGC 原生 UI：FlyView 右上角多机面板 (FlyViewTopRightPanel)
            //  - 概念差异：QGC 是"单机激活"模式（activeVehicle 为当前
            //    控制的无人机），本面板为"多选批量操作"模式
            //
            //  【真实数据映射示例】（把 droneModel 换成 vehicles 后）：
            //    idStr        → vehicle.id
            //    dist         → vehicle.distanceToHome（字段以实际 fact 为准）
            //    relH         → vehicle.altitudeRelative.rawValue
            //    absH         → vehicle.altitudeAMSL.rawValue
            //    airSpeed     → vehicle.airSpeed.rawValue
            //    groundSpeed  → vehicle.groundSpeed.rawValue
            //    battery      → vehicle.batteries（QGC 5.0.8 为电池列表）
            // ============================================================

            // ==========顶部蓝色标题栏【多机列表 + 全选CheckBox】==========
            Rectangle {
                id:righttop
//                Layout.fillWidth: true
                anchors.top:parent.top
                height: 30
                width: parent.width
                color: "#2178dd"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin:5
                    anchors.rightMargin:15
                    spacing: 8
                    Image {
                        id: duoji
                        source: "file:///D:/GCS LOGE/svg//duojiliebiao.svg"
                        Layout.alignment: Qt.AlignVCenter
                        fillMode: Image.PreserveAspectFit
                                Layout.preferredWidth:righttop.height*0.7
                                Layout.preferredHeight:righttop.height*0.7
                                clip:true
                    }
                    Text {
                        text: "多机列表"
                        color: "white"
                        font.pixelSize:18
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    // 占位，把复选框挤到最右边
                    Item{
                        Layout.fillWidth:true
                    }
                    CheckBox {
                        id: checkAllBox
                        Layout.alignment: Qt.AlignVCenter
                        // 【重复功能】"全选"批量勾选：QGC 无全选概念，
                        // 对应 QGC 多机切换/激活机制（activeVehicle）
                        text: qsTr("全选")
                        checked: allChecked
                        onCheckedChanged: {
                            // 点击全选框，批量设置model所有项的selected
                            for(let i=0; i<droneModel.count; i++){
                                droneModel.get(i).selected = checked
                            }
                        }
                        // ========== 自定义复选框方框大小，修改这里的 implicitWidth / implicitHeight ==========
                        indicator: Rectangle {
                            implicitWidth: 20    // 方框总宽度，调大这个
                            implicitHeight: 20    // 方框总高度，调大这个
                            x: checkAllBox.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 10
                            border.color: "lightslategray"
                            color: checkAllBox.checked ? "#42A5F5" : "transparent"
                            // 里面的对勾方块
                            Text{
                                text: "√"
                                color: "white"
                                font.pixelSize: 18
                                x: parent.implicitWidth/2 - width/2
                                y: parent.implicitHeight/2 - height/2
                                visible: checkAllBox.checked
                            }
                        }
                    }
                }
            }
            // 无人机数据模型
            // 【演示用静态数据】接入真实多机后应替换为
            // model: QGroundControl.multiVehicleManager.vehicles
            ListModel {
                id: droneModel
                ListElement { idStr: "001"; dist:"77.6 m"; relH:"1000 m"; absH:"1000 m"; airSpeed:"0.0 m/s"; groundSpeed:"0.0 m/s"; battery:"50%"; selected: true }
                ListElement { idStr: "002"; dist:"77.6 m"; relH:"1000 m"; absH:"1000 m"; airSpeed:"0.0 m/s"; groundSpeed:"0.0 m/s"; battery:"50%"; selected: true }
                ListElement { idStr: "003"; dist:"77.6 m"; relH:"1000 m"; absH:"1000 m"; airSpeed:"0.0 m/s"; groundSpeed:"0.0 m/s"; battery:"50%"; selected: true }
                ListElement { idStr: "004"; dist:"77.6 m"; relH:"1000 m"; absH:"1000 m"; airSpeed:"0.0 m/s"; groundSpeed:"0.0 m/s"; battery:"50%"; selected: true }
                ListElement { idStr: "005"; dist:"77.6 m"; relH:"1000 m"; absH:"1000 m"; airSpeed:"0.0 m/s"; groundSpeed:"0.0 m/s"; battery:"50%"; selected: true }
            }

            ColumnLayout {
                anchors.top:righttop.bottom
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                //anchors.fill: parent

                // ==========无人机列表ListView==========
                ListView {
//                    anchors.top: righttop.bottom
//                    anchors.bottom: rightToolbarcol.bottom
//                    Layout.fillWidth: true
//                    height: rightToolbarcol.height - righttop.height
                    Layout.fillHeight: true
                    Layout.fillWidth: true
//                    Layout.fillHeight: true
                    model: droneModel
                     delegate:Rectangle{
                        width: parent.width
                        height: (rightToolbarcol.height-righttop.height)/5
                        visible: true
                        color:"#D01A3D8F"
                        border.color: "#1A3D8F"
                        // ========== 整行点击区域 ==========
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        // 点击整行，翻转选中状态
                                        model.selected = !model.selected
                                        // 【对应功能】可在此同时切换 QGC 激活机：
                                        // QGroundControl.multiVehicleManager.activeVehicle = 对应Vehicle
                                    }
                                }
                        ColumnLayout{
                            anchors.fill: parent
                            RowLayout{
                                Layout.fillWidth: true
                                //复选框
                                CheckBox {
                                    checked: model.selected
                                    onCheckedChanged: {
                                        if(model.selected !== checked){
                                            model.selected = checked
                                        }
                                    }
                                }
                                Text{
                                    text:"ID:"+idStr
                                    color: "yellow"
                                }
                                ColumnLayout{
                                    Layout.fillHeight: true
                                    Text{
                                        text:"位置{x,y}"
                                        color: "cyan"
                                    }
                                    //进度条
                                    ProgressBar {
                                        id:batterypercentage
                                        Layout.fillWidth: parent
                                        value:0.6
                                        padding:2
                                        // 【重复功能】电量 ≈ QGC 电池电量 fact
                                        // （vehicle.batteries，QGC 5.0.8 为电池列表，
                                        //  绑定示例：value: vehicle.batteries.get(0).chargeState.rawValue / 100.0）

                                        // 背景底板
                                        background: Rectangle {
                                            implicitWidth:batterypercentage.width
                                            implicitHeight:8
                                            color:"#E5E5E5"
                                            radius:4
                                        }
                                        // 填充内容
                                        contentItem: Item {
                                            Rectangle {
                                                width: batterypercentage.visualPosition * parent.width
                                                height:parent.height
                                                color:"#2196F3"
                                                radius:3
                                            }
                                        }

                                    }
                                }
                                Text{
                                    text:"电量:    "
                                    color: "yellow"
                                }
                            }
                            GridLayout{
                                columns: 3
                                columnSpacing:40
                                rowSpacing:10
                                Text{text: "离家距离"}
                                Text{text: "相对高度"}
                                Text{text: "海拔高度"}
                                Text{text: "空速"}
                                Text{text: "地速"}
                            }
                        }
                    }
                }
            }
        }

     //右侧显示栏收放按钮
        Button{

            id:button2
            width: button1.width
            height: button1.height
//            anchors.right: rightToolbarcol.left
            anchors.verticalCenter:button1.verticalCenter
            checkable: true
            icon.source: "file:///D:/GCS LOGE/svg/rightarrow2.svg"
            x: rightToolbarcol.visible?rightToolbarcol.x - button2.width : rightToolbarcol.x + rightToolbarcol.width
            Behavior on x {
                NumberAnimation { duration:200; easing.type: Easing.OutCubic }
            }
            background: Rectangle{
                anchors.fill: parent
                color:{
                    if (button2.pressed) {
                        return "white"
                    }
                    else if (button2.hovered) {
                        return "blue"
                    }
                    else {
                        return "blue"
                    }
                }
                opacity: {
                    if (button2.pressed) {
                        return 0.5
                    }else if(button2.hovered){
                        return 0.5
                    }else{
                        return 0.7
                    }
                }
            }
            onClicked: {
                console.log("click")
                showToolbar2 = !showToolbar2; // 点击取反，切换显示隐藏
            }
        }

//底部任务栏
        Rectangle{
            id:bottomToolbarcol
            height: gcs.height*0.2
            width: gcs.width*0.9
            visible: true
            color: "#801A3D8F"
//            opacity: 0.8
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
//            Rectangle {
//                    anchors.fill: parent
//                    color: "#c01A3D8F"
//                    opacity: 0.1
//                    radius: 12
//                }
//            RowLayout{
//                anchors.fill: parent
                //底部左边工具栏
                GridLayout{
                    id:leftTool
                    width: bottomToolbarcol.width * 0.35
                    columns: 5
                    rowSpacing:15
                    anchors.left: bottomToolbarcol.left
                    anchors.leftMargin: 15
                    anchors.bottom: bottomToolbarcol.bottom
                    anchors.bottomMargin: 15
                    Repeater {
                        Layout.fillWidth: true
                            // model 改成对象数组：每项包含 text 和 icon 两个字段
                            model: [
                                { "text": "起飞", "icon": "file:///D:/Qt_work/qml000/icon/qifei.svg"},
                                { "text": "降落", "icon": "file:///D:/Qt_work/qml000/icon/jiangluo.svg"},
                                { "text": "巡航", "icon": "file:///D:/Qt_work/qml000/icon/xvnhang.svg"},
                                { "text": "返航", "icon": "file:///D:/Qt_work/qml000/icon/fanhang.svg"},
                                { "text": "开伞\n降落", "icon": "file:///D:/Qt_work/qml000/icon/jiangluosan.svg"},
                                { "text": "定量\n爬升", "icon": "file:///D:/Qt_work/qml000/icon/pasheng.svg"},
                                { "text": "定量\n下降", "icon": "file:///D:/Qt_work/qml000/icon/xiajiang.svg"},
                                { "text": "高度\n调节", "icon": "file:///D:/Qt_work/qml000/icon/hight.svg"},
                                { "text": "动力\n关车", "icon": "file:///D:/Qt_work/qml000/icon/guanji.svg"},
                                { "text": "取消\n关车", "icon": "file:///D:/Qt_work/qml000/icon/quxiaocolse.svg"}
                            ]

                            Button {
                                id: bottombutton
                                Layout.preferredWidth: (bottomToolbarcol.width*0.4 - 6)*0.15
                                Layout.preferredHeight: (bottomToolbarcol.height*0.6 - 45)/1.5
                                checkable: true
                                contentItem:Item{
                                    anchors.fill: parent
                                    RowLayout{
                                        anchors.centerIn: parent
                                        Image{
                                            source: modelData.icon
                                            fillMode: Image.PreserveAspectFit
                                            Layout.preferredWidth:parent.width*0.5
                                            Layout.preferredHeight:parent.width*0.5
                                            clip:true
                                        }
                                        Text{
                                            Layout.fillWidth: true
                                            text: modelData.text
                                            color: "white"
                                            font.pixelSize: 15
                                            font.bold: true
                                        }
                                    }
                                }
                                background: Rectangle{
                                    anchors.fill: parent
                                    radius: 4
                                    color:bottombutton.pressed? "white":"blue"
                                    opacity: bottombutton.hovered? 0.5:1
                                }
                                // ====================================================
                                // 【与 QGC 引导动作对应表】(GuidedActionsController，
                                //  经由 globals.guidedControllerFlyView 即 flyView.guidedController)
                                //   0 起飞      →【重复功能】actionTakeoff（QGC 起飞确认滑块）
                                //   1 降落      →【重复功能】actionLand
                                //   2 巡航      →  自定义（可映射 actionChangeSpeed 定速）
                                //   3 返航      →【重复功能】actionRTL（QGC RTL 按钮）
                                //   4 开伞降落  →  自定义开伞（QGC 无）+【重复】降落部分
                                //   5 定量爬升  →【部分重复】actionChangeAlt（改高度）
                                //   6 定量下降  →【部分重复】actionChangeAlt（改高度）
                                //   7 高度调节  →【部分重复】actionChangeAlt（改高度）
                                //   8 动力关车  →【重复功能】actionEmergencyStop（电机急停）
                                //   9 取消关车  →  自定义（恢复动力 ≈ actionArm 部分重复）
                                //  confirmAction 会走 QGC 自带确认滑块/对话框，
                                //  想跳过确认可改用 executeAction(...)
                                // ====================================================
                                onClicked: {
                                    var gc = globals.guidedControllerFlyView
                                    if (!globals.activeVehicle) {
                                        return
                                    }
                                    switch (index) {
                                    case 0: gc.confirmAction(gc.actionTakeoff);        break
                                    case 1: gc.confirmAction(gc.actionLand);           break
                                    case 3: gc.confirmAction(gc.actionRTL);            break
                                    case 8: gc.confirmAction(gc.actionEmergencyStop);  break
                                    default: break // 2/4/5/6/7/9：自定义或待接入
                                    }
                                }
                            }
                        }
                }

                //底部中间仪表盘
                // ============================================================
                // 【重复功能】姿态仪/罗盘 ≈ QGC FlyView 内置
                // 姿态仪表(VehicleAttitudeWidget)与罗盘(VehicleCompassWidget)，
                // 数据源：activeVehicle.roll / pitch / heading
                // 当前为空 Rectangle 占位，后续可把 QGC 仪表组件嵌到这里
                // ============================================================
                RowLayout{
                    id:yibiaopan
                    anchors.centerIn: parent
                    Rectangle{
                        id:shuipoingyi
                        width: bottomToolbarcol.width*0.37
                        height: bottomToolbarcol.width*0.37
                        radius: shuipoingyi.width/2
                        visible: true
                    }
                    Rectangle{
                        id:hangxiangjiao
                        width: bottomToolbarcol.width*0.37
                        height: bottomToolbarcol.width*0.37
                        radius: hangxiangjiao.width/2
                        visible: true
                    }

                }
                //底部右边工具栏
                // ============================================================
                // 【重复功能】遥测数值卡片 ≈ QGC FlyView 仪表数值区
                // (HorizontalFactValueGrid / InstrumentValueArea，
                //  QGC 原生支持自定义要显示的 fact 项)
                // 【真实数据映射示例】（替换 modelData.value 的静态值）：
                //   距原点距离/距航点距离 → vehicle.distanceToHome 等（以实际 fact 为准）
                //   空速       → vehicle.airSpeed.rawValue
                //   海拔高度   → vehicle.altitudeAMSL.rawValue
                //   对地高度   → vehicle.altitudeRelative.rawValue
                //   爬升率     → vehicle.climbRate.rawValue
                //   地速       → vehicle.groundSpeed.rawValue
                //   电池电压   → vehicle.batteries（QGC 5.0.8 为电池列表）
                //   GPS星数    → GPS 相关 fact（以实际 fact 为准）
                // ============================================================
                GridLayout{
                    id:buttomrighttoll
//                    width: bottomToolbarcol.width * 0.35
//                    columns: 5
//                    columnSpacing:(bottomToolbarcol.width*0.4 -6)*0.05
//                    rowSpacing:15
//                    anchors.right: bottomToolbarcol.right
//                    anchors.rightMargin: 15
//                    anchors.bottom: bottomToolbarcol.bottom
//                    anchors.bottomMargin: 15
                    width: leftTool.width
                    height: leftTool.height
                    columns: 5
                    rowSpacing:15
                    anchors.right: bottomToolbarcol.right
                    anchors.rightMargin: 15
                    anchors.bottom: bottomToolbarcol.bottom
                    anchors.bottomMargin: 15
                    Repeater{
                        Layout.fillWidth: true
                        model: [
                                    { "text": "开伞降落", "value": "00:00:00" },
                                    { "text": "距原点距离", "value": "0.0 m" },
                                    { "text": "空速", "value": "0.0 m/s" },
                                    { "text": "海拔高度", "value": "---.--" },
                                    { "text": "电池电压", "value": "---.--" },
                                    { "text": "GPS星数", "value": "0" },
                                    { "text": "距航点距离", "value": "0 m" },
                                    { "text": "地速", "value": "0.0 m/s" },
                                    { "text": "对地高度", "value": "---.-- m" },
                                    { "text": "爬升率", "value": "0.0 m/s" }
                                ]
                                Rectangle {
                                    Layout.fillWidth: true
//                                    Layout.preferredHeight: 30
                                    Layout.preferredHeight: (buttomrighttoll.height - 8) / 2
                                    color: "#0a1929"             // 卡片底色（接近黑）
                                    border.color: "#4a9eff"      // 蓝色描边
                                    border.width: 2
                                    radius: 6                    // 圆角
                                    clip: true                    // 让内部两块被裁成圆角

                                    ColumnLayout {
                                        anchors.fill: parent
                                        spacing: 0

                                        //顶部：蓝色标签条
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: parent.height * 0.4
                                            color: "#1976D2"     // 蓝底
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.text
                                                color: "white"
                                                font.pixelSize: 14
                                                font.bold: true
                                            }
                                        }

                                        //底部：黑色数值区
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            color: "#000000"     // 黑底
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.value
                                                color: "white"
                                                font.pixelSize: 15
                                                font.bold: true
                                            }
                                        }
                                    }
                                }
                    }
                }
//                        Rectangle{
//                            width: (bottomToolbarcol.width*0.4 -6)*0.4
//                            height:(bottomToolbarcol.height*0.6-45)/1.5
//                            Button{
//                                anchors.fill: parent
//                                text: modelData
//                                background: Rectangle {
//                                        color: "dodgerblue"
//                                }
//                            }
//                        }
        }
    }
// ============================================================================
// ===================【自定义布局叠加层 结束】=================================
// ============================================================================

    footer: LogReplayStatusBar {   ///窗口底部状态栏：日志回放条，设置里开启才显示。
        visible: QGroundControl.settingsManager.flyViewSettings.showLogReplayStatusBar.rawValue
    }

    ///(辅助)调试、高级模式开关
    MessageDialog {   ///触摸区域调试弹窗
        ///开发调试用彩蛋弹窗，弹出=触摸区域可视化开关已经翻转（打开/关闭）。开启后，界面上所有可点击、触摸控件会绘制彩色边框，用来排查平板触屏点击区域错位、热区大小问题，普通用户完全看不到这个弹窗。
        id:                 showTouchAreasNotification   ///调试弹窗，开启触摸区域可视化
        title:              qsTr("Debug Touch Areas")
        text:               qsTr("Touch Area display toggled")
        buttons:            MessageDialog.Ok   ///只有一个【Ok】确认按钮
    }

    ///开启高级模式确认弹窗
    MessageDialog {
        ///专家模式开启确认框。打开后，QGC会解锁普通用户默认隐藏的功能：Analyze Tools日志分析菜单、更多底层参数、调试面板、MAVLink 原始报文查看等，面向飞控开发者/调参人员
        id:                 advancedModeOnConfirmation
        title:              qsTr("Advanced Mode")
        text:               QGroundControl.corePlugin.showAdvancedUIMessage
        buttons:            MessageDialog.Yes | MessageDialog.No   ///同时显示【Yes 确认】和【No 取消】两个按钮
        onButtonClicked: function (button, role) {   ///弹窗按钮点击回调函数
            if (button === MessageDialog.Yes) {
                QGroundControl.corePlugin.showAdvancedUI = true   ///打开全局高级UI开关
            }
        }
    }

    ///关闭高级模式确认弹窗
    MessageDialog {
        ///关闭高级模式的确认弹窗，关闭后，Analyze Tools、专家调试面板等高级菜单自动隐藏，回到普通用户界面
        id:                 advancedModeOffConfirmation
        title:              qsTr("Advanced Mode")
        text:               qsTr("Turn off Advanced Mode?")   ///"是否关闭高级模式？"
        buttons:            MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {   ///点击回调
            if (button === MessageDialog.Yes) {
                QGroundControl.corePlugin.showAdvancedUI = false   ///点击Yes时，`showAdvancedUI=false`，把高级UI全局开关关掉
            }
        }
    }

    ///工具选择侧边面板（主菜单抽屉）
    function showToolSelectDialog() {
        ///主窗口实例，负责页面切换、抽屉开关; 功能：打开汉堡侧边抽屉面板的触发函数
        if (mainWindow.allowViewSwitch()) {   ///判断当前是否允许切换视图（飞行中、某些锁定页面时会返回false，禁止打开菜单）
            mainWindow.showIndicatorDrawer(toolSelectComponent, null)   ///调用主窗口接口，把`toolSelectComponent`这个组件渲染成侧边滑出抽屉
        }
    }

    ///组件定义
    Component {   ///`Component`：QML 动态组件模板，给抽屉提供内容载体
        id: toolSelectComponent

        ToolIndicatorPage {   ///QGC封装的抽屉页面容器
            id:         toolSelectDialog
            //title:      qsTr("Select Tool")

            ///内部布局和按钮
            property real _toolButtonHeight:    ScreenTools.defaultFontPixelHeight * 3   ///`_toolButtonHeight`：菜单按钮高度，根据屏幕字体大小自适应（适配平板/手机/电脑不同DPI）
            property real _margins:             ScreenTools.defaultFontPixelWidth   ///`_margins`：面板边距，同样自适应屏幕

            contentComponent: Component {
                ColumnLayout {
                    width:  innerLayout.width + (toolSelectDialog._margins * 2)
                    height: innerLayout.height + (toolSelectDialog._margins * 2)

                    ColumnLayout {
                        id:             innerLayout
                        Layout.margins: toolSelectDialog._margins
                        spacing:        ScreenTools.defaultFontPixelWidth
                        ///所有菜单按钮放在这里纵向排列

                        ///'SubMenuButton':封装好的菜单按钮控件
                        SubMenuButton {   ///Plan Flight 飞行规划按钮
                            height:             toolSelectDialog._toolButtonHeight
                            Layout.fillWidth:   true
                            text:               qsTr("Plan Flight")
                            imageResource:      "/qmlimages/Plan.svg"
                            onClicked: {   ///点击回调
                                if (mainWindow.allowViewSwitch()) {   ///先判断是否允许视图切换
                                    mainWindow.closeIndicatorDrawer()   ///`closeIndicatorDrawer()`：关闭侧边抽屉
                                    mainWindow.showPlanView()   ///跳转到航点规划页面
                                }
                            }
                        }

                        SubMenuButton {   ///Analyze Tools 分析工具按钮
                            id:                 analyzeButton
                            height:             toolSelectDialog._toolButtonHeight
                            Layout.fillWidth:   true
                            text:               qsTr("Analyze Tools")
                            imageResource:      "/qmlimages/Analyze.svg"
                            visible:            QGroundControl.corePlugin.showAdvancedUI   ///默认隐藏，只有高级模式开关 `showAdvancedUI=true` 时，按钮才可见
                            onClicked: {   ///点击,关闭抽屉,打开日志/飞行数据分析页面
                                if (mainWindow.allowViewSwitch()) {
                                    mainWindow.closeIndicatorDrawer()
                                    mainWindow.showAnalyzeTool()
                                }
                            }
                        }

                        SubMenuButton {   ///Vehicle Configuration 飞控 / 载具配置按钮
                            id:                 setupButton
                            height:             toolSelectDialog._toolButtonHeight
                            Layout.fillWidth:   true
                            text:               qsTr("Vehicle Configuration")
                            imageResource:      "/qmlimages/Gears.svg"
                            onClicked: {   ///点击,跳转到飞控参数、硬件、载具配置页面
                                if (mainWindow.allowViewSwitch()) {
                                    mainWindow.closeIndicatorDrawer()
                                    mainWindow.showVehicleConfig()
                                }
                            }
                        }

                        SubMenuButton {   ///Application Settings 软件设置按钮
                            id:                 settingsButton
                            height:             toolSelectDialog._toolButtonHeight
                            Layout.fillWidth:   true
                            text:               qsTr("Application Settings")
                            imageResource:      "/res/QGCLogoFull.svg"
                            imageColor:         "transparent"
                            visible:            !QGroundControl.corePlugin.options.combineSettingsAndSetup   ///如果配置项开启【合并设置和载具配置】，这个按钮就隐藏
                            onClicked: {   ///点击，打开QGC软件本身的全局设置（语言、连接、界面等）
                                if (mainWindow.allowViewSwitch()) {
                                    drawer.close()
                                    mainWindow.showSettingsTool()
                                }
                            }
                        }

                        SubMenuButton {   ///Close关闭QGC按钮（仅全屏模式可见）
                            id:                 closeButton
                            height:             toolSelectDialog._toolButtonHeight
                            Layout.fillWidth:   true
                            text:               qsTr("Close %1").arg(QGroundControl.appName)
                            imageResource:      "/res/cancel.svg"
                            visible:            mainWindow.visibility === Window.FullScreen   ///只有QGC处于全屏模式时才显示这个关闭按钮，窗口模式看不到
                            onClicked: {
                                if (mainWindow.allowViewSwitch()) {
                                    mainWindow.finishCloseProcess()   ///`finishCloseProcess()`：执行关闭程序流程
                                }
                            }
                        }

                        ///底部版本号文字区域
                        ColumnLayout {
                            width:                  innerLayout.width
                            spacing:                0
                            Layout.alignment:       Qt.AlignHCenter

                            QGCLabel {
                                id:                     versionLabel
                                text:                   qsTr("%1 Version").arg(QGroundControl.appName)   ///第一行`QGroundControl Version`
                                font.pointSize:         ScreenTools.smallFontPointSize
                                wrapMode:               QGCLabel.WordWrap
                                Layout.maximumWidth:    parent.width
                                Layout.alignment:       Qt.AlignHCenter
                            }

                            QGCLabel {
                                text:                   QGroundControl.qgcVersion   ///具体版本号字符串
                                font.pointSize:         ScreenTools.smallFontPointSize
                                wrapMode:               QGCLabel.WrapAnywhere
                                Layout.maximumWidth:    parent.width
                                Layout.alignment:       Qt.AlignHCenter

                                QGCMouseArea {   ///版本号区域的鼠标/触摸热区，承载彩蛋逻辑;把前面3个MessageDialog弹窗串起来的逻辑
                                    id:                 easterEggMouseArea
                                    anchors.topMargin:  -versionLabel.height
                                    anchors.fill:       parent

                                    onClicked: (mouse) => {
                                        if (mouse.modifiers & Qt.ControlModifier) {   ///Ctrl + 点击
                                            QGroundControl.corePlugin.showTouchAreas = !QGroundControl.corePlugin.showTouchAreas   ///翻转触摸热区可视化开关
                                            showTouchAreasNotification.open()   ///打开`showTouchAreasNotification`提示弹窗
                                        } else if (ScreenTools.isMobile || mouse.modifiers & Qt.ShiftModifier) {   ///移动端长按 / PC端 Shift+点击
                                            mainWindow.closeIndicatorDrawer()
                                            if(!QGroundControl.corePlugin.showAdvancedUI) {
                                                advancedModeOnConfirmation.open()
                                            } else {
                                                advancedModeOffConfirmation.open()
                                            }
                                        }
                                    }

                                    // This allows you to change this on mobile
                                    onPressAndHold: {   ///手机端长按：切换触摸区域可视化
                                        QGroundControl.corePlugin.showTouchAreas = !QGroundControl.corePlugin.showTouchAreas
                                        showTouchAreasNotification.open()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ///工具抽屉（配置页、分析页、设置页都放这里）
    Rectangle {
        id:             toolDrawer
        anchors.fill:   parent
        visible:        false
        color:          qgcPal.window

        property var backIcon
        property string toolTitle
        property alias toolSource:  toolDrawerLoader.source
        property var toolIcon

        onVisibleChanged: {
            if (!toolDrawer.visible) {
                toolDrawerLoader.source = ""
            }
        }

        // This need to block click event leakage to underlying map.
        DeadMouseArea {   ///`DeadMouseArea`：吃掉鼠标点击，防止点击穿透到底下地图（抽屉打开时，不能点地图）
            anchors.fill: parent
        }

        Rectangle {   ///顶部返回栏，点返回关闭抽屉
            id:             toolDrawerToolbar
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    parent.top
            height:         ScreenTools.toolbarHeight
            color:          qgcPal.toolbarBackground

            RowLayout {
                id:                 toolDrawerToolbarLayout
                anchors.leftMargin: ScreenTools.defaultFontPixelWidth
                anchors.left:       parent.left
                anchors.top:        parent.top
                anchors.bottom:     parent.bottom
                spacing:            ScreenTools.defaultFontPixelWidth

                QGCLabel {
                    font.pointSize: ScreenTools.largeFontPointSize
                    text:           "<"
                }

                QGCLabel {
                    id:             toolbarDrawerText
                    text:           qsTr("Exit") + " " + toolDrawer.toolTitle
                    font.pointSize: ScreenTools.largeFontPointSize
                }
            }

            QGCMouseArea {
                anchors.fill: toolDrawerToolbarLayout
                onClicked: {
                    if (mainWindow.allowViewSwitch()) {
                        toolDrawer.visible = false
                    }
                }
            }
        }

        Loader {   ///加载工具QML页面;Loader动态加载不同工具页面
            id:             toolDrawerLoader
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    toolDrawerToolbar.bottom
            anchors.bottom: parent.bottom

            Connections {
                target:                 toolDrawerLoader.item
                ignoreUnknownSignals:   true
                onPopout:               toolDrawer.visible = false   ///子页面发出 `popout` 信号时自动关闭抽屉
            }
        }
    }

    //-------------------------------------------------------------------------
    //-- Critical Vehicle Message Popup

    ///criticalVehicleMessagePopup：飞行器严重告警弹窗
    function showCriticalVehicleMessage(message) {
        closeIndicatorDrawer()
        if (criticalVehicleMessagePopup.visible || QGroundControl.videoManager.fullScreen) {
            // We received additional warning message while an older warning message was still displayed.
            // When the user close the older one drop the message indicator tool so they can see the rest of them.
            criticalVehicleMessagePopup.additionalCriticalMessagesReceived = true
        } else {
            criticalVehicleMessagePopup.criticalVehicleMessage      = message
            criticalVehicleMessagePopup.additionalCriticalMessagesReceived = false
            criticalVehicleMessagePopup.open()
        }
    }

    Popup {   ///居中告警弹窗，红色警告样式
        id:                 criticalVehicleMessagePopup
        y:                  ScreenTools.toolbarHeight + ScreenTools.defaultFontPixelHeight
        x:                  Math.round((mainWindow.width - width) * 0.5)
        width:              mainWindow.width  * 0.55
        height:             criticalVehicleMessageText.contentHeight + ScreenTools.defaultFontPixelHeight * 2
        modal:              false
        focus:              true

        property alias  criticalVehicleMessage:             criticalVehicleMessageText.text
        property bool   additionalCriticalMessagesReceived: false

        background: Rectangle {
            anchors.fill:   parent
            color:          qgcPal.alertBackground
            radius:         ScreenTools.defaultFontPixelHeight * 0.5
            border.color:   qgcPal.alertBorder
            border.width:   2

            Rectangle {
                anchors.horizontalCenter:   parent.horizontalCenter
                anchors.top:                parent.top
                anchors.topMargin:          -(height / 2)
                color:                      qgcPal.alertBackground
                radius:                     ScreenTools.defaultFontPixelHeight * 0.25
                border.color:               qgcPal.alertBorder
                border.width:               1
                width:                      vehicleWarningLabel.contentWidth + _margins
                height:                     vehicleWarningLabel.contentHeight + _margins

                property real _margins: ScreenTools.defaultFontPixelHeight * 0.25

                QGCLabel {
                    id:                 vehicleWarningLabel
                    anchors.centerIn:   parent
                    text:               qsTr("Vehicle Error")
                    font.pointSize:     ScreenTools.smallFontPointSize
                    color:              qgcPal.alertText
                }
            }

            Rectangle {
                id:                         additionalErrorsIndicator
                anchors.horizontalCenter:   parent.horizontalCenter
                anchors.bottom:             parent.bottom
                anchors.bottomMargin:       -(height / 2)
                color:                      qgcPal.alertBackground
                radius:                     ScreenTools.defaultFontPixelHeight * 0.25
                border.color:               qgcPal.alertBorder
                border.width:               1
                width:                      additionalErrorsLabel.contentWidth + _margins
                height:                     additionalErrorsLabel.contentHeight + _margins
                visible:                    criticalVehicleMessagePopup.additionalCriticalMessagesReceived

                property real _margins: ScreenTools.defaultFontPixelHeight * 0.25

                QGCLabel {
                    id:                 additionalErrorsLabel
                    anchors.centerIn:   parent
                    text:               qsTr("Additional errors received")
                    font.pointSize:     ScreenTools.smallFontPointSize
                    color:              qgcPal.alertText
                }
            }
        }

        QGCLabel {
            id:                 criticalVehicleMessageText
            width:              criticalVehicleMessagePopup.width - ScreenTools.defaultFontPixelHeight
            anchors.centerIn:   parent
            wrapMode:           Text.WordWrap
            color:              qgcPal.alertText
            textFormat:         TextEdit.RichText
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                criticalVehicleMessagePopup.close()
                if (criticalVehicleMessagePopup.additionalCriticalMessagesReceived) {
                    criticalVehicleMessagePopup.additionalCriticalMessagesReceived = false;
                    flyView.dropMainStatusIndicatorTool();
                } else {
                    QGroundControl.multiVehicleManager.activeVehicle.resetErrorLevelMessages();
                }
            }
        }
    }

    //-------------------------------------------------------------------------
    //-- Indicator Drawer

    ///indicatorDrawer：指示器抽屉（汉堡菜单、状态指示器弹出面板）
    function showIndicatorDrawer(drawerComponent, indicatorItem) {
        ///`indicatorDrawer`：轻量弹出面板，比如汉堡主菜单、点击某个状态图标弹出小面板；跟随点击位置居中弹出，可展开
        indicatorDrawer.sourceComponent = drawerComponent
        indicatorDrawer.indicatorItem = indicatorItem
        indicatorDrawer.open()
    }

    function closeIndicatorDrawer() {
        indicatorDrawer.close()
    }

    Popup {   ///自动计算弹出X位置：跟着点击的按钮居中
        id:             indicatorDrawer
        x:              calcXPosition()
        y:              ScreenTools.toolbarHeight + _margins
        leftInset:      0
        rightInset:     0
        topInset:       0
        bottomInset:    0
        padding:        _margins * 2
        visible:        false
        modal:          true
        focus:          true
        closePolicy:    Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property var sourceComponent
        property var indicatorItem

        property bool _expanded:    false
        property real _margins:     ScreenTools.defaultFontPixelHeight / 4

        function calcXPosition() {
            if (indicatorItem) {
                var xCenter = indicatorItem.mapToItem(mainWindow.contentItem, indicatorItem.width / 2, 0).x
                return Math.max(_margins, Math.min(xCenter - (contentItem.implicitWidth / 2), mainWindow.contentItem.width - contentItem.implicitWidth - _margins - (indicatorDrawer.padding * 2) - (ScreenTools.defaultFontPixelHeight / 2)))
            } else {
                return _margins
            }
        }

        onOpened: {
            _expanded                               = false;
            indicatorDrawerLoader.sourceComponent   = indicatorDrawer.sourceComponent
        }
        onClosed: {
            _expanded                               = false
            indicatorItem                           = undefined
            indicatorDrawerLoader.sourceComponent   = undefined
        }

        background: Item {
            Rectangle {
                id:             backgroundRect
                anchors.fill:   parent
                color:          QGroundControl.globalPalette.window
                radius:         indicatorDrawer._margins
                opacity:        0.85
            }

            Rectangle {
                anchors.horizontalCenter:   backgroundRect.right
                anchors.verticalCenter:     backgroundRect.top
                width:                      ScreenTools.largeFontPixelHeight
                height:                     width
                radius:                     width / 2
                color:                      QGroundControl.globalPalette.button
                border.color:               QGroundControl.globalPalette.buttonText
                visible:                    indicatorDrawerLoader.item && indicatorDrawerLoader.item.showExpand && !indicatorDrawer._expanded

                QGCLabel {
                    anchors.centerIn:   parent
                    text:               ">"
                    color:              QGroundControl.globalPalette.buttonText
                }

                QGCMouseArea {
                    fillItem: parent
                    onClicked: indicatorDrawer._expanded = true
                }
            }
        }

        contentItem: QGCFlickable {
            id:             indicatorDrawerLoaderFlickable
            implicitWidth:  Math.min(mainWindow.contentItem.width - (2 * indicatorDrawer._margins) - (indicatorDrawer.padding * 2), indicatorDrawerLoader.width)
            implicitHeight: Math.min(mainWindow.contentItem.height - ScreenTools.toolbarHeight - (2 * indicatorDrawer._margins) - (indicatorDrawer.padding * 2), indicatorDrawerLoader.height)
            contentWidth:   indicatorDrawerLoader.width
            contentHeight:  indicatorDrawerLoader.height

            Loader {
                id: indicatorDrawerLoader

                Binding {
                    target:     indicatorDrawerLoader.item
                    property:   "expanded"
                    value:      indicatorDrawer._expanded
                }

                Binding {
                    target:     indicatorDrawerLoader.item
                    property:   "drawer"
                    value:      indicatorDrawer
                }
            }
        }
    }

    // We have to create the popup windows for the Analyze pages here so that the creation context is rooted
    // to mainWindow. Otherwise if they are rooted to the AnalyzeView itself they will die when the analyze viewSwitch
    // closes.
    ///分析页面的弹窗窗口必须在 mainWindow 上下文创建；如果在 AnalyzeView 内部创建，切走 AnalyzeView 时窗口对象会被销毁直接消失。
    ///作用：把日志分析页面脱离主窗口，单独弹出一个独立窗口。

    /// windowedAnalyzePage:独立窗口化分析页面
    function createrWindowedAnalyzePage(title, source) {
        var windowedPage = windowedAnalyzePage.createObject(mainWindow)
        windowedPage.title = title
        windowedPage.source = source
    }

    Component {
        id: windowedAnalyzePage

        Window {  ///独立子窗口，用来把分析页面弹出成单独窗口
            width:      ScreenTools.defaultFontPixelWidth  * 100
            height:     ScreenTools.defaultFontPixelHeight * 40
            visible:    true

            property alias source: loader.source

            Rectangle {
                color:          QGroundControl.globalPalette.window
                anchors.fill:   parent

                Loader {
                    id:             loader
                    anchors.fill:   parent
                    onLoaded:       item.popped = true
                }
            }

            onClosing: {
                visible = false
                source = ""
            }
        }
    }

    ///UTMSP 空域激活状态栏
    Connections{   ///`Connections`：信号绑定
        ///- 当状态栏内部触发 `activationTriggered(value)` 信号时，把值赋值给顶层的 `_utmspSendActTrigger`
        ///- 而 `_utmspSendActTrigger` 又传递给 flyView，实现：**状态栏点击激活 → 主窗口标记触发 → FlyView 内部下发 UTMSP 激活指令**
         target: activationbar
         function onActivationTriggered(value){
              _utmspSendActTrigger= value
         }
    }

    UTMSPActivationStatusBar{   ///`UTMSPActivationStatusBar`：UTMSP自定义状态栏组件，铺满整个窗口
        ///绑定：激活时间戳、是否获批激活、飞行ID，数据从 `UTMSPStateStorage`（全局存储对象）和 `utmspManager` 取
         id:                         activationbar
         activationStartTimestamp:   UTMSPStateStorage.startTimeStamp
         activationApproval:         UTMSPStateStorage.showActivationTab && QGroundControl.utmspManager.utmspVehicle.vehicleActivation
         flightID:                   UTMSPStateStorage.flightID
         anchors.fill:               parent
    }
}
