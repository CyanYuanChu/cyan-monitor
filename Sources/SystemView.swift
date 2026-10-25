import SwiftUI
import Charts
struct SystemSettingsView:View {
    @ObservedObject var monitor:SystemMonitor
    @ObservedObject var settings:MenuBarSettings
    @ObservedObject var startup:StartupManager
    var p:GrovePalette
    var body:some View {
        let r=monitor.reading
        VStack(alignment:.leading,spacing:24){
            SectionHeading(eyebrow:"SYSTEM / MENU BAR",title:"抬眼，就能看见。",subtitle:"同一个菜单栏项目内紧凑排列，显示内容可分别开关。")
            StartupSettingsView(manager: startup, p: p)
            HStack(spacing:12){GroveTile(title:"CPU 使用率",value:SystemReading.percent(r.cpu),detail:"全部核心的平均占用",icon:"cpu",p:p);GroveTile(title:"内存占用",value:SystemReading.memory(r.memoryUsed),detail:"共 "+SystemReading.memory(r.memoryTotal),icon:"memorychip",p:p);GroveTile(title:"磁盘已用",value:SystemReading.bytes(r.diskUsed),detail:"共 "+SystemReading.bytes(r.diskTotal),icon:"internaldrive",p:p)}
            HStack(spacing:14){GroveTile(title:"下载",value:SystemReading.rate(r.download),detail:"↓ 物理网络接口合计",icon:"arrow.down",p:p);GroveTile(title:"上传",value:SystemReading.rate(r.upload),detail:"↑ 物理网络接口合计",icon:"arrow.up",p:p)}
            VStack(alignment:.leading,spacing:16){Text("菜单栏显示内容").font(.system(size:15,weight:.semibold));ForEach(MenuMetric.allCases){metric in HStack{Label(metric.title,systemImage:metric.icon);Spacer();Toggle(metric.title,isOn:Binding(get:{settings.enabled.contains(metric.rawValue)},set:{settings.set(metric,$0)})).labelsHidden().toggleStyle(.switch).tint(p.accent)}.font(.system(size:12)).padding(.vertical,5)};Text("CPU、内存和磁盘合并排列；按住 ⌘ 可拖动整组。关闭不常看的数据可进一步节省空间。").font(.system(size:10)).foregroundStyle(p.secondary)}.padding(24).background(p.card,in:RoundedRectangle(cornerRadius:20))
            VStack(alignment:.leading,spacing:12){HStack{Text("CPU · 最近两分钟").font(.system(size:13,weight:.medium));Spacer();Text("0–100%").font(.system(size:10)).foregroundStyle(p.secondary)};Chart(Array(monitor.history.enumerated()),id:\.offset){i,value in AreaMark(x:.value("采样",i),y:.value("使用率",value)).foregroundStyle(p.accent.opacity(0.12));LineMark(x:.value("采样",i),y:.value("使用率",value)).foregroundStyle(p.accent)}.chartYScale(domain:0...100).chartXAxis(.hidden).frame(height:100)}.padding(24).background(p.card,in:RoundedRectangle(cornerRadius:20))
            Text("内存按虚拟内存页估算，排除可清除与文件缓存，可能与活动监视器略有差异。磁盘统计主目录所在卷；网速统计 en* 物理接口，避免重复计算 VPN 与虚拟网桥流量。").font(.system(size:10)).foregroundStyle(p.secondary).lineSpacing(5)
        }
    }
}

