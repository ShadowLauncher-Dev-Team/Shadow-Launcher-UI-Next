
/* =============================================================
   Shadow 资源库 · 数据与视觉生成
   ============================================================= */
var CATS = {
  mod:      { label:'模组',   en:'MODS',      icon:'package',  unit:'个' },
  shader:   { label:'光影',   en:'SHADERS',   icon:'sun',      unit:'款' },
  pack:     { label:'资源包', en:'RESOURCE',  icon:'palette',  unit:'个' },
  modpack:  { label:'整合包', en:'MODPACKS',  icon:'boxes',    unit:'个' },
  datapack: { label:'数据包', en:'DATAPACKS', icon:'database', unit:'个' }
};
var CAT_ORDER = ['mod','shader','pack','modpack','datapack'];

var ICONS = {
  search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
  x: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
  'chevron-down': '<path d="m6 9 6 6 6-6"/>',
  'chevron-left': '<path d="m15 18-6-6 6-6"/>',
  'chevron-right': '<path d="m9 18 6-6-6-6"/>',
  'arrow-left': '<path d="m12 19-7-7 7-7"/><path d="M19 12H5"/>',
  'arrow-right': '<path d="M5 12h14"/><path d="m12 5 7 7-7 7"/>',
  download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" x2="12" y1="15" y2="3"/>',
  package: '<path d="m7.5 4.27 9 5.15"/><path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/><path d="m3.3 7 8.7 5 8.7-5"/><path d="M12 22V12"/>',
  boxes: '<path d="M2.97 12.92A2 2 0 0 0 2 14.63v3.24a2 2 0 0 0 .97 1.71l3 1.8a2 2 0 0 0 2.06 0L12 19v-5.5l-5-3-4.03 2.42Z"/><path d="m7 16.5-4.74-2.85"/><path d="m7 16.5 5-3"/><path d="M7 16.5v5.17"/><path d="M12 13.5V19l3.97 2.38a2 2 0 0 0 2.06 0l3-1.8a2 2 0 0 0 .97-1.71v-3.24a2 2 0 0 0-.97-1.71L17 10.5l-5 3Z"/><path d="m17 16.5-5-3"/><path d="m17 16.5 4.74-2.85"/><path d="M17 16.5v5.17"/><path d="M7.97 4.42A2 2 0 0 0 7 6.13v4.37l5 3 5-3V6.13a2 2 0 0 0-.97-1.71l-3-1.8a2 2 0 0 0-2.06 0l-3 1.8Z"/><path d="M12 8 7.26 5.15"/><path d="m12 8 4.74-2.85"/><path d="M12 13.5V8"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>',
  palette: '<circle cx="13.5" cy="6.5" r=".5" fill="currentColor"/><circle cx="17.5" cy="10.5" r=".5" fill="currentColor"/><circle cx="8.5" cy="7.5" r=".5" fill="currentColor"/><circle cx="6.5" cy="12.5" r=".5" fill="currentColor"/><path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.554C21.965 6.012 17.461 2 12 2z"/>',
  database: '<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5V19A9 3 0 0 0 21 19V5"/><path d="M3 12A9 3 0 0 0 21 12"/>',
  layers: '<path d="m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65"/><path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  'check-circle': '<path d="M21.801 10A10 10 0 1 1 17 3.335"/><path d="m9 11 3 3L22 4"/>',
  clock: '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
  calendar: '<path d="M8 2v4"/><path d="M16 2v4"/><rect width="18" height="18" x="3" y="4" rx="2"/><path d="M3 10h18"/>',
  'external-link': '<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
  bookmark: '<path d="m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16z"/>',
  'share-2': '<circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" x2="15.42" y1="13.51" y2="17.49"/><line x1="15.41" x2="8.59" y1="6.51" y2="10.49"/>',
  star: '<polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>',
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  user: '<path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
  'alert-triangle': '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
  info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
  'shield-check': '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/>',
  sliders: '<line x1="4" x2="4" y1="21" y2="14"/><line x1="4" x2="4" y1="10" y2="3"/><line x1="12" x2="12" y1="21" y2="12"/><line x1="12" x2="12" y1="8" y2="3"/><line x1="20" x2="20" y1="21" y2="16"/><line x1="20" x2="20" y1="12" y2="3"/><line x1="2" x2="6" y1="14" y2="14"/><line x1="10" x2="14" y1="8" y2="8"/><line x1="18" x2="22" y1="16" y2="16"/>',
  zap: '<path d="M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z"/>',
  map: '<path d="M14.106 5.553a2 2 0 0 0 1.788 0l3.659-1.83A1 1 0 0 1 21 4.619v12.764a1 1 0 0 1-.553.894l-4.553 2.277a2 2 0 0 1-1.788 0l-4.212-2.106a2 2 0 0 0-1.788 0l-3.659 1.83A1 1 0 0 1 3 19.381V6.618a1 1 0 0 1 .553-.894l4.553-2.277a2 2 0 0 1 1.788 0z"/><path d="M15 5.764v15"/><path d="M9 3.236v15"/>',
  'refresh-cw': '<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/>',
  cpu: '<rect width="16" height="16" x="4" y="4" rx="2"/><rect width="6" height="6" x="9" y="9" rx="1"/><path d="M15 2v2"/><path d="M15 20v2"/><path d="M2 15h2"/><path d="M2 9h2"/><path d="M20 15h2"/><path d="M20 9h2"/><path d="M9 2v2"/><path d="M9 20v2"/>',
  monitor: '<rect width="20" height="14" x="2" y="3" rx="2"/><line x1="8" x2="16" y1="21" y2="21"/><line x1="12" x2="12" y1="17" y2="21"/>',
  'hard-drive': '<line x1="22" x2="2" y1="12" y2="12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/><line x1="6" x2="6.01" y1="16" y2="16"/><line x1="10" x2="10.01" y1="16" y2="16"/>',
  'file-archive': '<path d="M10 12a2 2 0 0 0-2 2v2a2 2 0 0 0 2 2h4a2 2 0 0 0 2-2v-2a2 2 0 0 0-2-2z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M20 2v6"/><path d="M20 8v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8"/><path d="M9 15h.01"/><path d="M12 15h.01"/><path d="M15 15h.01"/>',
  heart: '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/>',
  play: '<polygon points="6 3 20 12 6 21 6 3"/>',
  'more-horizontal': '<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>',
  grid: '<rect width="7" height="7" x="3" y="3" rx="1"/><rect width="7" height="7" x="14" y="3" rx="1"/><rect width="7" height="7" x="14" y="14" rx="1"/><rect width="7" height="7" x="3" y="14" rx="1"/>',
  list: '<path d="M8 6h13"/><path d="M8 12h13"/><path d="M8 18h13"/><path d="M3 6h.01"/><path d="M3 12h.01"/><path d="M3 18h.01"/>',
  sparkles: '<path d="m12 3-1.9 5.8a2 2 0 0 1-1.3 1.3L3 12l5.8 1.9a2 2 0 0 1 1.3 1.3L12 21l1.9-5.8a2 2 0 0 1 1.3-1.3L21 12l-5.8-1.9a2 2 0 0 1-1.3-1.3Z"/><path d="M5 3v4"/><path d="M19 17v4"/><path d="M3 5h4"/><path d="M17 19h4"/>',
  link: '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
  globe: '<circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/>',
  github: '<path d="M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.403 5.403 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4"/><path d="M9 18c-4.51 2-5-2-7-2"/>',
  tag: '<path d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z"/><circle cx="7.5" cy="7.5" r=".5" fill="currentColor"/>',
  filter: '<polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"/>',
  'arrow-up-right': '<path d="M7 7h10v10"/><path d="M7 17 17 7"/>'
};
function icon(name, size){
  var s = size || 16;
  return '<svg class="ic" width="' + s + '" height="' + s + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (ICONS[name] || '') + '</svg>';
}

/* ---------- 数据 ---------- */
var ITEMS = [
  /* ===== 模组 ===== */
  { id:'sodium', cat:'mod', kind:'perf', cn:'钠', en:'Sodium', author:'CaffeineMC', tags:['性能优化','渲染','客户端'], env:'客户端',
    dl:24183094, upd:2, rating:4.9, versions:['1.21.3','1.21.1','1.20.6','1.20.4','1.19.4','1.18.2'],
    fv:'0.6.9', fs:'1.2 MB', loader:'Fabric · NeoForge', license:'LGPL-3.0', source:'Modrinth', srcId:'AANobbMI',
    hue:['#38bdf8','#1d4ed8'], motif:'blades', hero:true, pick:true, note:'性能优化首选',
    intro:'在不改变任何方块与光影效果的前提下重写 Minecraft 的区块渲染管线。中低端显卡上的提升最明显，高端显卡则表现为更低的帧时间抖动。',
    p2:'它把原版的区块网格每帧重建改成了按需重建，并把顶点数据搬到更紧凑的缓冲区里。结果是同样的画面、同样的材质包，帧率却能翻一倍，而画面看不出任何差别。',
    p3:'因为不写入存档、不改动游戏逻辑，Sodium 可以随时加入或移除。与 Iris 同时使用时，光影的渲染同样会走这条新管线。',
    deps:[{n:'Fabric Loader', v:'≥ 0.16.0', req:'必需'},{n:'Fabric API', v:'可选，安装 Iris 时需要', req:'建议'},{n:'Indium', v:'用于第三方渲染模组兼容', req:'可选'}],
    shots:['1.21.3 + Iris 下的默认画面','同类优化模组叠加后的帧时间对比'] },

  { id:'iris', cat:'mod', kind:'perf', cn:'彩虹光影', en:'Iris Shaders', author:'Iris Team', tags:['光影','渲染','客户端'], env:'客户端',
    dl:12406332, upd:5, rating:4.8, versions:['1.21.3','1.21.1','1.20.6','1.20.4','1.19.4'],
    fv:'1.8.1', fs:'2.4 MB', loader:'Fabric · NeoForge', license:'LGPL-3.0', source:'Modrinth', srcId:'YL57xq9U',
    hue:['#a78bfa','#4c1d95'], motif:'waves', hero:true, pick:true, note:'光影入门首选',
    intro:'让光影包在 Fabric 与 NeoForge 上稳定运行，并完整支持 Sodium 的渲染优化。装上它，Complementary、BSL 这类光影包就能直接在原版画面上生效。',
    p2:'Iris 兼容绝大多数 OptiFine 光影的语法，包括阴影、体积光与自定义后处理。它把着色器编译搬到后台线程，切换光影时不再整段黑屏。',
    p3:'如果你之前用 OptiFine 跑光影，迁移到 Iris + Sodium 通常能多出 20 到 40 帧。设置里可以按光影包单独保存画质档位。',
    deps:[{n:'Sodium', v:'≥ 0.6.0', req:'必需'},{n:'Fabric Loader', v:'≥ 0.16.0', req:'必需'}],
    shots:['Complementary 在 1.21.3 下的表现','水面反射与体积光的调试视图'] },

  { id:'create', cat:'mod', kind:'content', cn:'机械动力', en:'Create', author:'simibubi', tags:['科技','机械','自动化'], env:'双端',
    dl:18924551, upd:3, rating:4.9, versions:['1.21.1','1.20.6','1.20.4','1.20.1','1.19.2','1.18.2'],
    fv:'6.0.4', fs:'14.8 MB', loader:'Forge · NeoForge · Fabric', license:'MIT', source:'CurseForge', srcId:'328085',
    hue:['#f59e0b','#9a3412'], motif:'rings', hero:true, pick:true, note:'编辑长测推荐',
    intro:'以旋转动力为核心的机械自动化模组。从手摇曲柄到蒸汽引擎，把风车、齿轮、机械臂组合成一套真正能运转的工厂。',
    p2:'Create 的每个部件都有实体模型与动画：传送带上的物品会真的移动，齿轮咬合时会真的转动。它把自动化做成了可以观赏的机械，而不是一排贴图。',
    p3:'模组自带一套任务式的进度引导，从第一台水车到列车与飞行器，足够支撑一整个存档的目标。安装时需要同时放入 Flywheel 前置。',
    deps:[{n:'Flywheel', v:'≥ 1.0.0', req:'必需'},{n:'Forge / NeoForge', v:'对应 MC 版本', req:'必需'},{n:'JEI', v:'配方查看，强烈建议', req:'建议'}],
    shots:['旋转动力的传动结构','列车与自动农场的组合产线'] },

  { id:'jei', cat:'mod', kind:'ui', cn:'物品管理器', en:'JEI', author:'mezz', tags:['界面','辅助','前置'], env:'客户端',
    dl:31220118, upd:7, rating:4.8, versions:['1.21.3','1.21.1','1.20.6','1.20.1','1.19.4'],
    fv:'19.21.0', fs:'1.1 MB', loader:'Forge · NeoForge · Fabric', license:'MIT', source:'CurseForge', srcId:'238222',
    hue:['#2dd4bf','#0f766e'], motif:'grid',
    intro:'把全部配方摊开在物品栏右侧，支持搜索、书签与按模组分类。装上一百个模组之后，你依然能一眼看清某件物品是怎么做出来的。',
    p2:'除了合成，JEI 还能显示熔炼、切石、酿造与模组自定义的配方类型。按 R 查用途、按 U 查来源，是大多数整合包玩家的默认操作。',
    p3:'它的 API 同时被大量模组当作配方展示的前置。若你发现某个模组的配方页是空的，多半是 JEI 版本落后于该模组。',
    shots:['配方面板与搜索建议','书签栏与多配方类型切换'] },

  { id:'lithium', cat:'mod', kind:'perf', cn:'锂', en:'Lithium', author:'CaffeineMC', tags:['性能优化','服务端','轻量'], env:'服务端', client:false,
    dl:9842117, upd:4, rating:4.7, versions:['1.21.3','1.21.1','1.20.6','1.20.4','1.19.4'],
    fv:'0.15.3', fs:'612 KB', loader:'Fabric', license:'LGPL-3.0', source:'Modrinth', srcId:'gvQqBUqZ',
    hue:['#34d399','#065f46'], motif:'grid',
    intro:'针对游戏逻辑层的通用优化，重写了实体、方块刻与 AI 的更新循环。几乎不改变任何可感知的行为，却能让服务器 tick 更稳。',
    p2:'它的改动集中在路径寻找、碰撞检测与流体更新，这些都是原版里最容易被忽略的性能黑洞。服务端装它，玩家端不需要。',
    p3:'与 Sodium 分工不同：Sodium 管渲染，Lithium 管逻辑，两者可以同时安装且互不冲突。',
    shots:['服务器 tick 时间对比','实体密集区域的路径寻找表现'] },

  { id:'dh', cat:'mod', kind:'perf', cn:'遥远的地平线', en:'Distant Horizons', author:'jeseibel', tags:['渲染','远景','性能'], env:'客户端',
    dl:6842190, upd:6, rating:4.6, versions:['1.21.3','1.21.1','1.20.6','1.20.1'],
    fv:'2.3.4', fs:'8.6 MB', loader:'Fabric · Forge', license:'LGPL-3.0', source:'Modrinth', srcId:'u1PU9r4K',
    hue:['#818cf8','#312e81'], motif:'waves', pick:true,
    intro:'把渲染距离从 12 个区块推向 512 个区块，用 LOD 地形替代远处未加载的区块。远景山脉第一次真正连成一片。',
    p2:'LOD 数据在后台逐步生成并缓存，第一次进入世界时会有一段加载时间，之后远近地形的衔接几乎无缝。',
    p3:'它和光影的兼容仍在推进，部分光影包需要关闭天空盒接管才能正常显示远景。低配机器建议把 LOD 距离压到 128。',
    shots:['512 区块远景下的山脉','与光影叠加时的地形衔接'] },

  { id:'farmers', cat:'mod', kind:'content', cn:'农夫乐事', en:'Farmer’s Delight', author:'vectorwing', tags:['农业','食物','装饰'], env:'双端',
    dl:7204333, upd:14, rating:4.9, versions:['1.21.1','1.20.6','1.20.1','1.19.2','1.18.2'],
    fv:'1.3.2', fs:'6.1 MB', loader:'Forge · Fabric', license:'MIT', source:'CurseForge', srcId:'398521',
    hue:['#84cc16','#3f6212'], motif:'hex',
    intro:'给农业与厨房补上一整套内容：新作物、新锅具、可放置的食物与一顿真正的晚餐。风格贴近原版，不破坏生存节奏。',
    p2:'切菜板、汤锅与炉灶构成了一条完整的烹饪链，食材可以自由组合成不同料理。所有方块都做了原版风格的模型与音效。',
    p3:'与大多数农业模组兼容，且被不少整合包当作食物系统的底座。建议同时安装 JEI 以查看料理配方。',
    shots:['厨房方块的摆放效果','作物与料理的完整配方链'] },

  { id:'fabric-api', cat:'mod', kind:'lib', cn:'Fabric API', en:'Fabric API', author:'modmuss50', tags:['前置','开发','核心'], env:'双端',
    dl:28110442, upd:1, rating:4.9, versions:['1.21.3','1.21.1','1.20.6','1.20.4','1.19.4'],
    fv:'0.115.0', fs:'1.9 MB', loader:'Fabric', license:'Apache-2.0', source:'Modrinth', srcId:'P7dR8mSH',
    hue:['#94a3b8','#334155'], motif:'grid',
    intro:'绝大多数 Fabric 模组的前置依赖，提供事件、注册表与渲染钩子。它本身不产生可见内容，但缺少它时，半个模组列表会直接加载失败。',
    p2:'除非某个模组明确要求更高的版本，否则保持它与 Minecraft 版本对齐即可。升级游戏版本时，记得同步更新它。',
    p3:'它不会出现在创造模式物品栏里，也不会增加启动时间，属于装完就忘的那一类模组。',
    shots:['模组列表中的前置标记','事件系统的调试输出'] },

  /* ===== 光影 ===== */
  { id:'complementary', cat:'shader', kind:'shader', cn:'互补重塑', en:'Complementary Reimagined', author:'EminGT', tags:['写实','平衡','光影'],
    dl:8204331, upd:1, rating:4.9, versions:['1.21.3','1.21.1','1.20.6','1.20.4','1.19.4'],
    fv:'5.4.1', fs:'12.6 MB', loader:'Iris · OptiFine', license:'自定义许可', source:'Modrinth', srcId:'HVbvNkCt',
    hue:['#60a5fa','#1e3a8a'], motif:'waves', hero:true, pick:true, note:'画面与性能平衡',
    intro:'在写实与性能之间取平衡的光影包。反射、体积光与阴影都做了分级，默认档位在中端显卡上也能保持 60 帧。',
    p2:'预设里提供了从「极速」到「电影级」的五档配置，切换只影响后处理开销，不需要重新加载游戏。',
    p3:'它的水面上反射、树叶透光与夜晚灯火是标志性效果，和 Terralith 这类地形包搭配时尤其好看。',
    deps:[{n:'Iris Shaders', v:'≥ 1.7.0', req:'必需'},{n:'Sodium', v:'≥ 0.6.0', req:'建议'}],
    shots:['晴天正午的水面反射','夜晚村落与体积光'] },

  { id:'bsl', cat:'shader', kind:'shader', cn:'BSL 光影', en:'BSL Shaders', author:'CaptTatsu', tags:['写实','柔和','光影'],
    dl:6120884, upd:16, rating:4.8, versions:['1.21.3','1.21.1','1.20.6','1.20.1','1.19.4'],
    fv:'8.4.1', fs:'4.2 MB', loader:'Iris · OptiFine', license:'自定义许可', source:'CurseForge', srcId:'326577',
    hue:['#fbbf24','#9a3412'], motif:'rings', pick:true,
    intro:'以柔和色调和干净的阴影著称的老牌光影。它不追求极限写实，而是让原版画面在保留辨识度的前提下更好看。',
    p2:'默认设置非常克制：暖色阳光、淡蓝色阴影、轻微的体积雾。正是这种克制让它适合长时间游玩。',
    p3:'对显卡要求中等，六年前的独显也能跑到 60 帧以上。缺点是水面反射相对简单，不太适合截图党。',
    shots:['黄昏时分的暖色光照','森林中的柔和阴影'] },

  { id:'photon', cat:'shader', kind:'shader', cn:'光子', en:'Photon Shader', author:'SixthSurge', tags:['写实','体积光','光影'],
    dl:2684020, upd:5, rating:4.7, versions:['1.21.3','1.21.1','1.20.6','1.20.4'],
    fv:'1.4.0', fs:'9.8 MB', loader:'Iris', license:'自定义许可', source:'Modrinth', srcId:'6f6Qh3mZ',
    hue:['#c084fc','#4c1d95'], motif:'waves', hero:true, pick:true, note:'新版本 · 体积光',
    intro:'强调体积光与大气散射的写实光影。云层、水面与日落的表现力很强，代价是对显卡的要求明显更高。',
    p2:'它重新实现了大气模型，天空的色温会随太阳高度真实变化，云层也有厚度与自阴影。',
    p3:'建议 8 GB 显存起步，且需要关闭其他会接管天空盒的模组。低配机器可以先从它的「性能」预设开始。',
    shots:['日落时的大气散射','厚云层与地面阴影'] },

  { id:'rethinking', cat:'shader', kind:'shader', cn:'体素重思', en:'Rethinking Voxels', author:'gri573', tags:['写实','体积云','光影'],
    dl:1842300, upd:8, rating:4.6, versions:['1.21.1','1.20.6','1.20.4'],
    fv:'0.13.1', fs:'7.4 MB', loader:'Iris', license:'自定义许可', source:'Modrinth', srcId:'qvIfYCYJ',
    hue:['#22d3ee','#0e7490'], motif:'grid',
    intro:'把光追思路带进 Iris：逐方块计算光照与阴影，让洞穴与室内不再是均匀的灰。需要较强的显卡。',
    p2:'它用体素化的方式重建方块阴影，火把与熔炉的光会真正照亮结构，而不是贴一张光照图。',
    p3:'显存占用明显高于同类，建议至少 16 GB 内存与 8 GB 显存。移动端核显不建议尝试。',
    shots:['洞穴内的逐方块光照','室内火把与阴影层次'] },

  { id:'bliss', cat:'shader', kind:'shader', cn:'极乐', en:'Bliss', author:'X0nk', tags:['梦幻','柔和','轻量'],
    dl:1204882, upd:3, rating:4.8, versions:['1.21.3','1.21.1','1.20.6','1.20.1'],
    fv:'2.1.2', fs:'5.6 MB', loader:'Iris', license:'自定义许可', source:'Modrinth', srcId:'hY07n3sV',
    hue:['#f0abfc','#86198f'], motif:'portal', pick:true,
    intro:'偏梦幻的柔和光影，色调偏粉、对比度低。适合建筑党与截图党，不太适合长时间生存。',
    p2:'雾气更浓、光晕更明显，配合建筑作品会有很强的绘本感。默认配置对显卡要求不高。',
    p3:'因为整体偏亮，洞穴里可能显得不够压抑。可以在设置里单独调低环境光。',
    shots:['清晨的粉色雾气','建筑群与柔和光晕'] },

  { id:'makeup', cat:'shader', kind:'shader', cn:'极速光影', en:'MakeUp Ultra Fast', author:'MGR', tags:['轻量','竞技','低配'],
    dl:982441, upd:33, rating:4.5, versions:['1.21.3','1.21.1','1.20.6','1.20.1'],
    fv:'9.8', fs:'3.1 MB', loader:'Iris · OptiFine', license:'自定义许可', source:'Modrinth', srcId:'412161',
    hue:['#a3e635','#4d7c0f'], motif:'blades',
    intro:'为低配机器设计的光影，保留基础阴影与水反射，把开销压到最低。核显笔记本也能开着它跑图。',
    p2:'它刻意削减了体积光与后处理层数，换来接近原版帧率的运行表现。适合 PVP 与老笔记本。',
    p3:'画质当然不能和光子相比，但在 60 帧与好看之间，它选择了前者。',
    shots:['默认档位的画质','开启阴影后的帧率表现'] },

  /* ===== 资源包 ===== */
  { id:'fresha', cat:'pack', kind:'pack', cn:'生动动画', en:'Fresh Animations', author:'FreshLX', tags:['动画','生物','细节'],
    dl:12204881, upd:2, rating:4.9, versions:['1.21.3','1.21.1','1.20.6','1.20.4','1.19.4'],
    fv:'1.9.2', fs:'26.4 MB', loader:'原版 · OptiFine', license:'自定义许可', source:'Modrinth', srcId:'50dA9Sha',
    hue:['#2dd4bf','#115e59'], motif:'pixel', hero:true, pick:true, note:'细节提升明显',
    intro:'给原版生物加上眨眼、转头、呼吸与攻击预备动作。贴图本身没变，但你会觉得它们突然活了。',
    p2:'它通过自定义实体模型实现逐骨骼动画，因此需要 OptiFine 或 CIT Resewn 才能完整生效。原版会回退成静态贴图。',
    p3:'资源包体积不小，但只影响生物模型。与多数材质包兼容，只要对方的生物贴图不是完全重绘。',
    shots:['村民的待机动作','僵尸与骷髅的攻击预备帧'] },

  { id:'faithful', cat:'pack', kind:'pack', cn:'忠实 32x', en:'Faithful 32x', author:'Faithful Team', tags:['高清','原版','32x'],
    dl:8842006, upd:5, rating:4.8, versions:['1.21.3','1.21.1','1.20.6','1.20.4','1.19.4'],
    fv:'1.21.4', fs:'18.2 MB', loader:'原版', license:'自定义许可', source:'Modrinth', srcId:'7aK5s0hQ',
    hue:['#94a3b8','#334155'], motif:'pixel', pick:true,
    intro:'严格遵循原版美术风格的高清重制，把 16x 贴图放大到 32x。适合想提升清晰度但不想改变观感的玩家。',
    p2:'所有贴图都按原版色板重绘，方块形状与配色完全一致，只是分辨率翻倍。远处看几乎察觉不到换了包。',
    p3:'32x 对显存几乎无压力，适合作为其他材质包的底包。也提供 64x 的独立版本。',
    shots:['主世界方块纹理','界面与物品图标'] },

  { id:'staytrue', cat:'pack', kind:'pack', cn:'保持真实', en:'Stay True', author:'FredBob', tags:['写实','原版','16x'],
    dl:6101884, upd:21, rating:4.8, versions:['1.21.3','1.21.1','1.20.6','1.20.1','1.19.4'],
    fv:'2.4.0', fs:'9.6 MB', loader:'原版', license:'自定义许可', source:'Modrinth', srcId:'317269',
    hue:['#34d399','#14532d'], motif:'iso', pick:true,
    intro:'保留原版配色与形状的写实化重制，加了细微的材质纹理与 AO。风格克制，适合长期生存。',
    p2:'它只在原版贴图上叠加极细的噪点与边缘过渡，不改变任何方块的可辨识度。',
    p3:'16x 分辨率意味着几乎零性能开销，配合光影时也不会因为分辨率和风格冲突而显得突兀。',
    shots:['草地与石头的细节','下界方块纹理'] },

  { id:'excalibur', cat:'pack', kind:'pack', cn:'石中剑', en:'Excalibur', author:'Maffhew', tags:['中世纪','奇幻','32x'],
    dl:4204882, upd:9, rating:4.6, versions:['1.21.3','1.21.1','1.20.6','1.20.1','1.19.4'],
    fv:'1.9.0', fs:'22.8 MB', loader:'原版', license:'自定义许可', source:'CurseForge', srcId:'323410',
    hue:['#eab308','#713f12'], motif:'hex', hero:true, pick:true,
    intro:'以中世纪奇幻为基调的 32x 资源包，重绘了全部界面、方块与装备。适合搭配建筑与 RPG 整合包。',
    p2:'整套 UI 都换成了深色石质与金边，物品栏、合成台与附魔台都有独立的重绘。',
    p3:'与同作者的 Excalibur 附属包组合使用效果最好。注意它的界面重绘会覆盖其他 UI 类资源包。',
    shots:['中世界村庄的建筑纹理','界面与装备图标'] },

  { id:'mizuno', cat:'pack', kind:'pack', cn:'水野工艺', en:'Mizuno 16 Craft', author:'Mizuno', tags:['极简','暖色','16x'],
    dl:3842119, upd:35, rating:4.7, versions:['1.21.3','1.21.1','1.20.6','1.20.1','1.19.4'],
    fv:'3.2.0', fs:'6.4 MB', loader:'原版', license:'自定义许可', source:'Modrinth', srcId:'321726',
    hue:['#fca5a5','#7f1d1d'], motif:'portal',
    intro:'暖色调的极简 16x 资源包，界面干净、方块柔和。作者坚持手绘，整体像一本安静的绘本。',
    p2:'所有贴图都降低了饱和度并加入暖色偏移，白天不会过曝，夜晚也不会太冷。',
    p3:'适合搭配柔和型光影。因为是手绘风格，与其他高清材质包混用时会有明显割裂。',
    shots:['暖色村庄的白天','室内与界面配色'] },

  { id:'betterleaves', cat:'pack', kind:'pack', cn:'更好的树叶', en:'Better Leaves', author:'Motschen', tags:['极简','细节','16x'],
    dl:2204884, upd:15, rating:4.9, versions:['1.21.3','1.21.1','1.20.6','1.20.4','1.19.4'],
    fv:'1.9.1', fs:'1.8 MB', loader:'原版', license:'MIT', source:'Modrinth', srcId:'bT4r6c2Q',
    hue:['#4ade80','#166534'], motif:'pixel',
    intro:'只做一件事：把原版的实心树叶换成带透明缝隙的模型，并补充树苗与藤蔓的细节。兼容绝大多数资源包。',
    p2:'它不改贴图颜色，只改模型与剔除方式，因此可以叠在几乎任何材质包之上。',
    p3:'体积不到 2 MB，对性能没有影响。想要更茂密的树冠可以再叠加它的「繁茂」附加包。',
    shots:['树冠的透明缝隙','不同树种的表现'] },

  /* ===== 整合包 ===== */
  { id:'atm10', cat:'modpack', kind:'modpack', cn:'全能 10', en:'All the Mods 10', author:'ATM Team', tags:['科技','大型','冒险'],
    dl:1284001, upd:4, rating:4.7, versions:['1.21.1','1.20.1','1.19.2'],
    fv:'4.3.0', fs:'1.84 GB', loader:'NeoForge 21.1.80', license:'自定义许可', source:'CurseForge', srcId:'925200',
    hue:['#fb923c','#7c2d12'], motif:'portal', hero:true, pick:true, note:'大型整合包新作',
    intro:'All the Mods 系列第十作，收录 400 多个模组，从科技、魔法到冒险一应俱全。开箱即有任务书引导，不需要自己拼装。',
    p2:'整合包已锁定全部模组的版本组合，并附带一组从入门到终局的任务。第一次进入世界时，按 J 键打开任务书。',
    p3:'建议分配 8 GB 内存，首次启动需要解压与下载约 1.8 GB 的模组文件。低配机器可以先用它的 Lite 版本。',
    deps:[{n:'NeoForge', v:'21.1.80', req:'必需'},{n:'Java 21', v:'≥ 21.0.4', req:'必需'},{n:'内存', v:'建议 8 GB 以上', req:'建议'}],
    shots:['任务书与开局基地','中期自动化产线'] },

  { id:'rlc', cat:'modpack', kind:'modpack', cn:'真实生存', en:'RLCraft', author:'Shivaxi', tags:['生存','硬核','冒险'],
    dl:3842551, upd:29, rating:4.6, versions:['1.12.2'],
    fv:'2.9.3', fs:'892 MB', loader:'Forge 14.23.5', license:'自定义许可', source:'CurseForge', srcId:'285109',
    hue:['#ef4444','#7f1d1d'], motif:'hex', hero:true, pick:true,
    intro:'以极限生存为目标的硬核整合包：真实的温度、口渴、受伤与怪物增强。第一次玩建议先看攻略，否则活不过第一晚。',
    p2:'它把生存拆成了温度、口渴、体力与部位伤害四套系统，任何一项失衡都可能致命。',
    p3:'整合包停留在 1.12.2，属于刻意不升级的类型。启动器会自动下载对应的老版本 Forge。',
    shots:['夜晚的怪物潮','生存状态与体温界面'] },

  { id:'cobblemon', cat:'modpack', kind:'modpack', cn:'方块宝可梦', en:'Cobblemon', author:'Cobblemon Team', tags:['RPG','冒险','生物'],
    dl:2104332, upd:2, rating:4.9, versions:['1.21.1','1.20.1','1.19.2'],
    fv:'1.7.0', fs:'640 MB', loader:'Fabric 0.16.9', license:'MIT', source:'Modrinth', srcId:'5FFgwNNP',
    hue:['#facc15','#854d0e'], motif:'portal', pick:true, note:'玩法最完整',
    intro:'把宝可梦带进 Minecraft 的整合包，包含完整的捕捉、对战与进化系统，并重构了世界生成以容纳新的生态。',
    p2:'野生宝可梦会按生物群系刷新，捕捉、培养、对战都有独立的界面与进度。整合包附带了引导任务。',
    p3:'服务端与客户端都需要安装。存档可以正常升级，但跨大版本更新前建议备份。',
    shots:['野外遭遇与捕捉','对战界面与队伍配置'] },

  { id:'prominence', cat:'modpack', kind:'modpack', cn:'普罗米嫩斯 II', en:'Prominence II RPG', author:'Ridanis', tags:['RPG','冒险','剧情'],
    dl:1842004, upd:7, rating:4.7, versions:['1.20.1','1.19.2'],
    fv:'2.8.4', fs:'1.24 GB', loader:'Fabric 0.15.7', license:'自定义许可', source:'Modrinth', srcId:'9k3mPq2L',
    hue:['#c084fc','#4c1d95'], motif:'waves',
    intro:'剧情驱动的 RPG 整合包，重做了战斗、技能树与地牢结构。适合想按主线推进而不是自由建造的玩家。',
    p2:'主线由任务书串起，每个章节都有独立的 Boss 与装备线。战斗引入了闪避、格挡与技能冷却。',
    p3:'内容量很大，建议留出至少 6 GB 内存。与光影搭配时优先选择轻量款以保住帧数。',
    shots:['章节 Boss 战','技能树与装备界面'] },

  { id:'bettermc', cat:'modpack', kind:'modpack', cn:'更好的 MC', en:'Better MC Fabric', author:'Luna Pixel Studios', tags:['优化','冒险','新手'],
    dl:1204882, upd:5, rating:4.6, versions:['1.21.1','1.20.6','1.20.1','1.19.4'],
    fv:'32.0', fs:'420 MB', loader:'Fabric 0.16.9', license:'自定义许可', source:'CurseForge', srcId:'636859',
    hue:['#4ade80','#166534'], motif:'iso',
    intro:'在保留冒险内容的同时做了大量性能与体验优化，开箱即玩，适合第一次接触整合包的新玩家。',
    p2:'默认启用了 Sodium、Iris 与一批体验类模组，进入游戏后可以直接开光影。',
    p3:'模组数量控制在 200 个以内，启动时间明显短于大型整合包，适合日常游玩。',
    shots:['默认画面与光影','新增结构与生物'] },

  { id:'astral', cat:'modpack', kind:'modpack', cn:'机械动力：星界', en:'Create: Astral', author:'LudoCrypt', tags:['科技','空岛','自动化'],
    dl:1002441, upd:12, rating:4.8, versions:['1.18.2'],
    fv:'2.4.1', fs:'780 MB', loader:'Forge 40.2.0', license:'自定义许可', source:'CurseForge', srcId:'654083',
    hue:['#60a5fa','#1e3a8a'], motif:'rings', pick:true,
    intro:'把机械动力与太空探索结合起来的空岛整合包。从一颗小行星开始，搭出能飞出大气层的生产线。',
    p2:'所有资源都需要通过机械动力的加工链从零合成，中期会解锁火箭与轨道站。',
    p3:'难度曲线偏硬，建议先熟悉 Create 的基础机制。整合包自带详细的任务引导。',
    shots:['空岛开局平台','火箭与轨道站'] },

  /* ===== 数据包 ===== */
  { id:'terralith', cat:'datapack', kind:'datapack', cn:'大地裂变', en:'Terralith', author:'Starmute', tags:['地形','世界生成','生态'],
    dl:2842119, upd:8, rating:4.9, versions:['1.21.3','1.21.1','1.20.6','1.20.1','1.19.4'],
    fv:'2.5.4', fs:'4.2 MB', loader:'原版 · 数据包', license:'自定义许可', source:'Modrinth', srcId:'8oi3MDTz',
    hue:['#2dd4bf','#134e4a'], motif:'iso', hero:true, pick:true, note:'地形重制标杆',
    intro:'用原版方块堆出 90 多种生物群系，不新增任何方块。山脉、峡谷与花海会以你熟悉的方式重新组合。',
    p2:'它只替换世界生成数据，所有地貌都靠原版方块组合而成，因此不会出现材质缺失。新建世界时启用效果最佳。',
    p3:'与原版结构、村庄兼容良好。若与 Tectonic 同时使用，需要按其说明调整加载顺序。',
    shots:['巨型峡谷与梯田','樱花林与高山湖泊'] },

  { id:'incendium', cat:'datapack', kind:'datapack', cn:'炼狱', en:'Incendium', author:'Starmute', tags:['下界','挑战','地形'],
    dl:1204882, upd:17, rating:4.8, versions:['1.21.3','1.21.1','1.20.6','1.20.1'],
    fv:'1.6.2', fs:'2.8 MB', loader:'原版 · 数据包', license:'自定义许可', source:'Modrinth', srcId:'2fR2r4hK',
    hue:['#f97316','#7c2d12'], motif:'waves', pick:true,
    intro:'重写下界的结构与生态，加入堡垒、火山与新的生物群系。下界不再是赶路的中转站。',
    p2:'新增的下界要塞与堡垒有独立的战利品表，掉落强度明显高于原版，适合中后期探索。',
    p3:'对已生成的下界区块无效，建议新建世界或使用未探索区域。与 Terralith 可以共存。',
    shots:['火山与熔岩湖','下界堡垒内部'] },

  { id:'nullscape', cat:'datapack', kind:'datapack', cn:'虚空之境', en:'Nullscape', author:'Starmute', tags:['末地','地形','奇幻'],
    dl:984331, upd:24, rating:4.7, versions:['1.21.3','1.21.1','1.20.6'],
    fv:'1.3.0', fs:'2.1 MB', loader:'原版 · 数据包', license:'自定义许可', source:'Modrinth', srcId:'6cQp2nVb',
    hue:['#a78bfa','#312e81'], motif:'portal',
    intro:'重构末地地形，把漂浮的岛屿做成有层次的虚空景观。适合截图，也适合把末地当成真正的终局地图。',
    p2:'末地岛屿的高度差被放大到 200 格以上，配合末地石与紫珀的配色，形成一种近乎超现实的景观。',
    p3:'建议搭配末地相关的结构数据包一起使用。对已探索的末地区块无效。',
    shots:['虚空中的浮岛群','末地城与紫珀森林'] },

  { id:'tectonic', cat:'datapack', kind:'datapack', cn:'构造', en:'Tectonic', author:'Apollounknowndev', tags:['地形','山脉','世界生成'],
    dl:1842004, upd:5, rating:4.8, versions:['1.21.3','1.21.1','1.20.6','1.20.4','1.20.1'],
    fv:'2.4.2', fs:'3.4 MB', loader:'原版 · 数据包', license:'MIT', source:'Modrinth', srcId:'4kR9m2Qc',
    hue:['#38bdf8','#0c4a6e'], motif:'iso', pick:true,
    intro:'极简的地形数据包，只调整噪声参数，却能让山脉更高、河谷更深。与原版结构兼容良好。',
    p2:'它不新增群系，而是把原版的地形曲线拉得更夸张。海拔落差可以达到 300 格以上。',
    p3:'与 Terralith 同时使用会得到更壮观的地貌，但需要按作者给出的顺序加载。',
    shots:['高山与深谷的落差','河谷与瀑布'] },

  { id:'vanillatweaks', cat:'datapack', kind:'datapack', cn:'原版微调', en:'Vanilla Tweaks', author:'Vanilla Tweaks', tags:['原版增强','合成','便利'],
    dl:4204881, upd:2, rating:4.9, versions:['1.21.3','1.21.1','1.20.6','1.20.1','1.19.4'],
    fv:'7.1.0', fs:'1.2 MB', loader:'原版 · 数据包', license:'自定义许可', source:'Vanilla Tweaks', srcId:'vanilla-tweaks',
    hue:['#94a3b8','#1e293b'], motif:'pixel',
    intro:'由社区维护的原版增强合集，按需勾选：更好的合成、更快的熔炉、可回收的物品。只改你想要的那几项。',
    p2:'官网提供可视化勾选器，生成的数据包只包含你选中的功能，不会塞进一整套改动。',
    p3:'它只改配方与进度逻辑，适合作为长期生存的底层增强。与大部分模组兼容。',
    shots:['配方改动示例','界面与提示'] },

  { id:'dungeons', cat:'datapack', kind:'datapack', cn:'地牢与酒馆', en:'Dungeons and Taverns', author:'Noca', tags:['结构','探索','建筑'],
    dl:1102441, upd:11, rating:4.7, versions:['1.21.3','1.21.1','1.20.6','1.20.1'],
    fv:'3.0.2', fs:'3.9 MB', loader:'原版 · 数据包', license:'自定义许可', source:'Modrinth', srcId:'8pQ2r5Tn',
    hue:['#fbbf24','#78350f'], motif:'hex', pick:true,
    intro:'在世界中追加地牢、酒馆与小型遗迹，密度经过调校，不会让地表变成迷宫。适合探索型生存。',
    p2:'结构内部有完整的战利品与机关，部分房间会生成友善的村民，可以当作临时据点。',
    p3:'与 Terralith、Tectonic 这类地形包兼容。已生成的区块不会追加结构，建议新建世界。',
    shots:['森林中的酒馆','地牢内部的机关'] }
];

var KIND_P2 = {
  perf:'所有优化都发生在渲染与逻辑层，不改变方块、配方或世界生成；因此它可以安全地加入现有存档，也可以随时移除。',
  content:'内容以数据驱动的方式注册，新增方块与物品会直接出现在创造模式物品栏中，不需要额外的配置文件。',
  ui:'它只接管界面层，不修改存档数据。若与其他界面模组冲突，可以在配置里单独关闭某个面板。',
  lib:'这是一个前置库，本身不提供可见内容，但被大量模组依赖。请让它与依赖方要求的版本保持一致。',
  shader:'光影包需要在 Iris 或 OptiFine 中加载。放入 shaderpacks 目录后，在视频设置的光影列表里选择即可。',
  pack:'资源包只替换贴图与模型，不影响游戏机制，可以随时切换。多人服务器上不需要服务端安装。',
  modpack:'整合包内已锁定所有模组的版本组合，启动器会自动补齐缺失文件，不需要你手动对齐版本。',
  datapack:'数据包通过 /datapack 指令启用，只影响世界生成、结构或进度逻辑，不改变客户端文件。'
};
var KIND_P3 = {
  perf:'如果你的整合包已经包含同类优化模组，建议只保留其中一个，并在启动前清理旧版本的残留文件，避免重复注入。',
  content:'多人服务器需要客户端与服务端同时安装；单人游戏直接放入 mods 目录即可，存档不会因此损坏。',
  ui:'首次安装后建议重启一次游戏，让界面注册表完整加载。快捷键可以在「控制」设置里重新绑定。',
  lib:'升级游戏版本时，请先确认依赖它的模组已经支持新版本，再一起更新，否则会出现加载顺序错误。',
  shader:'不同光影对显卡的要求差异很大，建议先从中档预设开始，再逐步打开体积光与水面反射。',
  pack:'若同时使用多个资源包，请把它放在列表靠上的位置；界面类资源包需要放在最上方才能生效。',
  modpack:'首次启动会解压大量文件，机械硬盘上可能需要几分钟，期间启动器看起来像卡住是正常现象。',
  datapack:'新建世界时启用效果最佳；已经生成的地形不会被改写，只会在未探索区域生效。'
};
var KIND_QUOTE = {
  perf:'真正好的模组不抢戏——它只是让原本卡顿的那半秒消失，然后你就再也回不去了。',
  content:'内容的重量不在数量，而在于你第一次看到传送带真的动起来时，会想立刻再造一条。',
  ui:'最好的界面模组是让人忘记界面的存在，只记得自己刚刚查到了想查的东西。',
  lib:'没人会感谢一个前置库，但每个人都会在它缺席的时候骂上一句。',
  shader:'光影的价值不在参数表，而在你按下 F5 之后，会不会想多站一会儿。',
  pack:'资源包是最便宜的重制：一个文件夹，换一整个世界的手感。',
  modpack:'整合包不是模组越多越好，而是让四百个模组看起来像本来就该在一起。',
  datapack:'最好的数据包不会让你意识到它存在，只会让你觉得这个世界本来就这么大。'
};
var KIND_SHOTS = {
  perf:['默认设置下的实际画面','与同类模组叠加后的性能对比'],
  content:['在 1.21.3 下的实际画面','完整内容链的展示'],
  ui:['主界面与面板布局','与整合包同时使用时的表现'],
  lib:['模组列表中的依赖关系','加载日志中的注册项'],
  shader:['晴天正午的画面','雨天与夜晚的氛围'],
  pack:['主世界白天纹理','室内与界面细节'],
  modpack:['开局主基地','中期自动化产线'],
  datapack:['生成的地貌与峡谷','村庄与地下结构']
};
var KIND_CHANGE = {
  perf:['适配 Minecraft {mc}，修复与渲染模组的加载顺序冲突','区块重建耗时下降约 6%，首次进入世界的卡顿减少'],
  content:['适配 Minecraft {mc}，补全新增方块的标签与配方','修正部分物品在创造模式栏中的排序'],
  ui:['适配 Minecraft {mc}，跟随新的界面缩放规则','修复在 4K 分辨率下搜索框错位的问题'],
  lib:['适配 Minecraft {mc}，补齐新版本的事件注册项','优化启动期注册表构建耗时'],
  shader:['适配 Minecraft {mc}，同步新的天空盒接口','微调水面反射的采样半径，减少闪烁'],
  pack:['适配 Minecraft {mc}，补齐新方块与物品的贴图','修正部分生物模型的 UV 偏移'],
  modpack:['适配 Minecraft {mc}，更新 12 个核心模组','调整任务书第三章的奖励平衡'],
  datapack:['适配 Minecraft {mc}，修正结构生成的高度限制','降低罕见地貌的出现概率，避免过度密集']
};

var KIND_DEPS = {
  perf:[{n:'Fabric Loader', v:'≥ 0.16.0', req:'必需'},{n:'Fabric API', v:'≥ 0.115.0', req:'建议'}],
  content:[{n:'对应加载器', v:'与 MC 版本匹配', req:'必需'},{n:'Flywheel', v:'部分科技模组需要', req:'可选'}],
  ui:[{n:'Fabric / Forge', v:'与 MC 版本匹配', req:'必需'}],
  lib:[{n:'Fabric Loader', v:'≥ 0.16.0', req:'必需'}],
  shader:[{n:'Iris Shaders', v:'≥ 1.7.0', req:'必需'},{n:'Sodium', v:'≥ 0.6.0', req:'建议'}],
  pack:[{n:'原版客户端', v:'1.20 – 1.21.3', req:'无需前置'}],
  modpack:[{n:'NeoForge / Fabric', v:'整合包内置', req:'必需'},{n:'Java', v:'≥ 21.0.4', req:'必需'},{n:'内存', v:'建议 8 GB 以上', req:'建议'}],
  datapack:[{n:'原版游戏', v:'1.20 – 1.21.3', req:'无需前置'}]
};

/* ---------- 工具 ---------- */
function itemById(id){
  for (var i = 0; i < ITEMS.length; i++) if (ITEMS[i].id === id) return ITEMS[i];
  return null;
}
function catItems(cat){
  var out = [];
  for (var i = 0; i < ITEMS.length; i++) if (ITEMS[i].cat === cat) out.push(ITEMS[i]);
  return out;
}
function heroCandidates(cat){
  var out = [];
  var all = catItems(cat);
  for (var i = 0; i < all.length; i++) if (all[i].hero) out.push(all[i]);
  if (out.length === 0) out = all.slice(0, 3);
  return out;
}
function fmtDl(n){
  if (n >= 100000000) return (n / 100000000).toFixed(2).replace('.00','').replace('.0','') + ' 亿';
  if (n >= 10000) return Math.round(n / 10000).toLocaleString('zh-CN') + ' 万';
  return String(n);
}
function fmtNum(n){ return Number(n).toLocaleString('zh-CN'); }
function updText(d){
  if (d <= 0) return '今天';
  if (d === 1) return '昨天';
  if (d < 7) return d + ' 天前';
  if (d < 14) return '1 周前';
  if (d < 30) return Math.floor(d / 7) + ' 周前';
  if (d < 60) return '1 个月前';
  return Math.floor(d / 30) + ' 个月前';
}
function buildsFor(it){
  if (it.builds) return it.builds;
  var parts = String(it.fv).split('.');
  var maj = parseInt(parts[0], 10) || 1;
  var min = parseInt(parts[1], 10) || 0;
  var pat = parseInt(parts[2], 10);
  if (isNaN(pat)) pat = 0;
  var out = [];
  for (var i = 0; i < 3; i++) {
    var p = pat - i;
    var m = min;
    if (p < 0) { p = 0; }
    var v = parts.length > 2 ? (maj + '.' + m + '.' + p) : (parts.length === 2 ? (maj + '.' + Math.max(0, min - i)) : String(maj - i));
    var size = i === 0 ? it.fs : (i === 1 ? it.fs : it.fs);
    out.push({ v:v, size:size });
  }
  return out;
}
function sizeMb(str){
  var s = String(str);
  var n = parseFloat(s);
  if (isNaN(n)) return 1;
  if (s.indexOf('GB') >= 0) return n * 1024;
  if (s.indexOf('KB') >= 0) return n / 1024;
  return n;
}
function dayStr(offset){
  var d = new Date(2026, 10, 6);
  d.setDate(d.getDate() - offset);
  var m = d.getMonth() + 1;
  var day = d.getDate();
  return d.getFullYear() + '-' + (m < 10 ? '0' + m : m) + '-' + (day < 10 ? '0' + day : day);
}
function depsFor(it){
  if (it.deps) return it.deps;
  return KIND_DEPS[it.kind] || KIND_DEPS.perf;
}
function shotsFor(it){
  if (it.shots) return it.shots;
  return KIND_SHOTS[it.kind] || KIND_SHOTS.perf;
}
function esc(s){
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/* ---------- 封面生成 ---------- */
var uid = 0;
function hashStr(s){
  var h = 2166136261;
  for (var i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
  return h >>> 0;
}
function mulberry(a){
  return function(){
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    var t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

var MOTIFS = {
  blades: function(id){
    return '<g>'
      + '<path d="M24 182 L212 22" stroke="url(#' + id + 'g)" stroke-width="1.1" opacity=".35"/>'
      + '<rect x="28" y="94" width="184" height="11" rx="5.5" fill="url(#' + id + 'g)" opacity=".9"/>'
      + '<rect x="52" y="116" width="148" height="7" rx="3.5" fill="url(#' + id + 'g)" opacity=".5"/>'
      + '<rect x="14" y="133" width="206" height="3" rx="1.5" fill="url(#' + id + 'g)" opacity=".26"/>'
      + '<circle cx="188" cy="56" r="29" fill="none" stroke="#fff" stroke-opacity=".12"/>'
      + '<circle cx="188" cy="56" r="13" fill="url(#' + id + 'g)" opacity=".38"/>'
      + '<path d="M150 154 l9 -9 M163 162 l13 -13" stroke="#fff" stroke-opacity=".2"/>'
      + '</g>';
  },
  rings: function(id){
    return '<g transform="translate(120 120)">'
      + '<circle r="80" fill="none" stroke="url(#' + id + 'g)" stroke-opacity=".3"/>'
      + '<circle r="61" fill="none" stroke="#fff" stroke-opacity=".1" stroke-dasharray="2 7"/>'
      + '<circle r="44" fill="none" stroke="url(#' + id + 'g)" stroke-opacity=".85" stroke-width="2"/>'
      + '<circle r="20" fill="url(#' + id + 'g)" opacity=".55"/>'
      + '<circle r="6" fill="#fff" opacity=".55"/>'
      + '<path d="M0 -80 A80 80 0 0 1 70 39" fill="none" stroke="#fff" stroke-opacity=".38" stroke-width="1.5"/>'
      + '<rect x="-2" y="-90" width="4" height="12" fill="#fff" opacity=".28"/>'
      + '<rect x="-86" y="-2" width="12" height="4" fill="#fff" opacity=".16"/>'
      + '</g>';
  },
  hex: function(id){
    return '<g transform="translate(120 120)">'
      + '<polygon points="0,-88 76,-44 76,44 0,88 -76,44 -76,-44" fill="none" stroke="url(#' + id + 'g)" stroke-opacity=".5"/>'
      + '<polygon points="0,-58 50,-29 50,29 0,58 -50,29 -50,-29" fill="url(#' + id + 'g)" fill-opacity=".16" stroke="#fff" stroke-opacity=".16"/>'
      + '<polygon points="0,-30 26,-15 26,15 0,30 -26,15 -26,-15" fill="url(#' + id + 'g)" opacity=".85"/>'
      + '<path d="M-96 0 H96" stroke="#fff" stroke-opacity=".06"/>'
      + '<path d="M0 -96 V-58 M0 58 V96" stroke="#fff" stroke-opacity=".07"/>'
      + '</g>';
  },
  iso: function(id){
    return '<g>'
      + '<path d="M120 46 L190 84 L120 122 L50 84 Z" fill="url(#' + id + 'g)" opacity=".78"/>'
      + '<path d="M50 84 L120 122 L120 186 L50 148 Z" fill="url(#' + id + 'g)" opacity=".3"/>'
      + '<path d="M190 84 L120 122 L120 186 L190 148 Z" fill="#05070a" opacity=".38"/>'
      + '<path d="M120 122 L190 84" stroke="#fff" stroke-opacity=".22"/>'
      + '<path d="M120 122 L50 84" stroke="#fff" stroke-opacity=".1"/>'
      + '<path d="M84 66 L154 104" stroke="#fff" stroke-opacity=".08"/>'
      + '<rect x="46" y="42" width="148" height="1" fill="#fff" opacity=".06"/>'
      + '</g>';
  },
  waves: function(id){
    return '<g fill="none" stroke="url(#' + id + 'g)" stroke-linecap="round">'
      + '<path d="M-16 72 C 26 44, 66 100, 118 72 S 208 44, 256 72" stroke-width="2" stroke-opacity=".85"/>'
      + '<path d="M-16 100 C 26 72, 66 128, 118 100 S 208 72, 256 100" stroke-width="1.5" stroke-opacity=".45"/>'
      + '<path d="M-16 128 C 26 100, 66 156, 118 128 S 208 100, 256 128" stroke-width="1.2" stroke-opacity=".22"/>'
      + '<path d="M-16 156 C 26 128, 66 184, 118 156 S 208 128, 256 156" stroke-width="1" stroke-opacity=".1"/>'
      + '<circle cx="176" cy="62" r="22" fill="url(#' + id + 'g)" stroke="none" opacity=".35"/>'
      + '<circle cx="176" cy="62" r="34" fill="none" stroke="#fff" stroke-opacity=".08"/>'
      + '</g>';
  },
  pixel: function(id){
    var r = mulberry(7);
    var s = '';
    for (var y = 0; y < 6; y++) {
      for (var x = 0; x < 6; x++) {
        var o = r();
        if (o < 0.35) continue;
        s += '<rect x="' + (46 + x * 25) + '" y="' + (46 + y * 25) + '" width="17" height="17" rx="2" fill="url(#' + id + 'g)" opacity="' + (0.08 + o * 0.4).toFixed(2) + '"/>';
      }
    }
    return '<g>'
      + '<rect x="34" y="34" width="172" height="172" rx="12" fill="none" stroke="#fff" stroke-opacity=".1"/>'
      + s
      + '<rect x="58" y="58" width="58" height="58" rx="7" fill="url(#' + id + 'g)" opacity=".8"/>'
      + '<rect x="126" y="92" width="42" height="42" rx="5" fill="url(#' + id + 'g)" opacity=".32"/>'
      + '<rect x="80" y="136" width="30" height="30" rx="4" fill="url(#' + id + 'g)" opacity=".2"/>'
      + '</g>';
  },
  portal: function(id){
    return '<g>'
      + '<path d="M78 186 V104 a42 42 0 0 1 84 0 V186 Z" fill="url(#' + id + 'g)" opacity=".2" stroke="url(#' + id + 'g)" stroke-opacity=".55"/>'
      + '<path d="M96 186 V108 a24 24 0 0 1 48 0 V186 Z" fill="url(#' + id + 'g)" opacity=".5"/>'
      + '<path d="M120 84 v102" stroke="#fff" stroke-opacity=".22"/>'
      + '<circle cx="120" cy="132" r="6" fill="#fff" opacity=".55"/>'
      + '<path d="M120 54 l4 9 9 4 -9 4 -4 9 -4 -9 -9 -4 9 -4 Z" fill="#fff" opacity=".55"/>'
      + '<path d="M62 70 l2 5 5 2 -5 2 -2 5 -2 -5 -5 -2 5 -2 Z" fill="#fff" opacity=".3"/>'
      + '<path d="M180 58 l2 5 5 2 -5 2 -2 5 -2 -5 -5 -2 5 -2 Z" fill="#fff" opacity=".25"/>'
      + '<path d="M40 186 H200" stroke="#fff" stroke-opacity=".12"/>'
      + '</g>';
  },
  grid: function(id){
    var s = '<g stroke="#fff" stroke-opacity=".07">';
    for (var i = 1; i < 6; i++) {
      s += '<path d="M' + (24 + i * 32) + ' 24 V216"/>';
      s += '<path d="M24 ' + (24 + i * 32) + ' H216"/>';
    }
    s += '</g>';
    return '<g>'
      + s
      + '<rect x="88" y="88" width="64" height="64" rx="8" fill="url(#' + id + 'g)" opacity=".72"/>'
      + '<rect x="120" y="56" width="8" height="8" rx="2" fill="#fff" opacity=".5"/>'
      + '<rect x="184" y="152" width="8" height="8" rx="2" fill="#fff" opacity=".3"/>'
      + '<rect x="56" y="152" width="8" height="8" rx="2" fill="#fff" opacity=".22"/>'
      + '<path d="M120 60 V88 M184 156 L152 152 M60 156 L88 152" stroke="#fff" stroke-opacity=".18"/>'
      + '</g>';
  }
};

function altMotif(m2){
  var order = ['blades','rings','hex','iso','waves','pixel','portal','grid'];
  var idx = order.indexOf(m2);
  if (idx < 0) return 'grid';
  return order[(idx + 3) % order.length];
}
function scene(it, w, h, opts){
  opts = opts || {};
  var hue = opts.hue || it.hue;
  var c1 = hue[0], c2 = hue[1];
  var rnd = mulberry(hashStr(it.id + (opts.v || '')));
  var id = 's' + (++uid);
  var m = Math.min(w, h);
  var scale = m / 240 * 1.06;
  var rot = Math.round((rnd() * 20 - 10) * 10) / 10;
  var wide = w / h > 1.45;
  var motif = MOTIFS[opts.motif || it.motif] || MOTIFS.grid;
  var groups = '';
  function place(x, y, sc, r, o){
    return '<g transform="translate(' + x + ' ' + y + ') rotate(' + r + ') scale(' + sc.toFixed(3) + ') translate(-120 -120)" opacity="' + o + '">' + motif(id, c1, c2) + '</g>';
  }
  if (wide) {
    groups += place(Math.round(w * 0.80), Math.round(h * 0.48), scale * 1.06, rot, 1);
    groups += place(Math.round(w * 0.405), Math.round(h * 0.53), scale * 0.56, rot - 13, 0.42);
    groups += place(Math.round(w * 0.185), Math.round(h * 0.58), scale * 0.30, rot + 18, 0.22);
    groups += place(Math.round(w * 0.972), Math.round(h * 0.40), scale * 0.36, rot - 21, 0.18);
  } else {
    groups += place(Math.round(w * 0.5), Math.round(h * 0.5), scale, rot, 1);
  }
  var dust = '';
  var dn = wide ? 18 : 9;
  for (var i = 0; i < dn; i++) {
    var dx = Math.round(rnd() * w);
    var dy = Math.round(rnd() * h);
    var rr = (0.7 + rnd() * 1.7).toFixed(1);
    var oo = (0.1 + rnd() * 0.3).toFixed(2);
    dust += '<circle cx="' + dx + '" cy="' + dy + '" r="' + rr + '" fill="#fff" opacity="' + oo + '"/>';
  }
  var svg = '<svg viewBox="0 0 ' + w + ' ' + h + '" preserveAspectRatio="xMidYMid slice" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">'
    + '<defs>'
    + '<linearGradient id="' + id + 'bg" x1="0" y1="0" x2="0.55" y2="1">'
    + '<stop offset="0" stop-color="#121a26"/><stop offset="0.5" stop-color="#0a0e15"/><stop offset="1" stop-color="#07090d"/>'
    + '</linearGradient>'
    + '<linearGradient id="' + id + 'g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="240" y2="240">'
    + '<stop offset="0" stop-color="' + c1 + '" stop-opacity=".95"/><stop offset="1" stop-color="' + c2 + '" stop-opacity=".72"/>'
    + '</linearGradient>'
    + '<radialGradient id="' + id + 'r" gradientUnits="userSpaceOnUse" cx="' + Math.round(w * 0.74) + '" cy="' + Math.round(h * 0.28) + '" r="' + Math.round(Math.max(w, h) * 0.68) + '">'
    + '<stop offset="0" stop-color="' + c1 + '" stop-opacity=".5"/><stop offset="0.5" stop-color="' + c2 + '" stop-opacity=".18"/><stop offset="1" stop-color="' + c2 + '" stop-opacity="0"/>'
    + '</radialGradient>'
    + '<radialGradient id="' + id + 'r2" gradientUnits="userSpaceOnUse" cx="' + Math.round(w * 0.1) + '" cy="' + Math.round(h * 0.9) + '" r="' + Math.round(Math.max(w, h) * 0.6) + '">'
    + '<stop offset="0" stop-color="' + c2 + '" stop-opacity=".2"/><stop offset="1" stop-color="' + c2 + '" stop-opacity="0"/>'
    + '</radialGradient>'
    + '<linearGradient id="' + id + 's" x1="0" y1="1" x2="1" y2="0">'
    + '<stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset="0.48" stop-color="#fff" stop-opacity=".05"/><stop offset="0.62" stop-color="#fff" stop-opacity="0"/>'
    + '</linearGradient>'
    + '<radialGradient id="' + id + 'v" cx="50%" cy="42%" r="78%">'
    + '<stop offset="0.4" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".55"/>'
    + '</radialGradient>'
    + '</defs>'
    + '<rect width="' + w + '" height="' + h + '" fill="url(#' + id + 'bg)"/>'
    + '<rect width="' + w + '" height="' + h + '" fill="url(#' + id + 'r)"/>'
    + '<rect width="' + w + '" height="' + h + '" fill="url(#' + id + 'r2)"/>'
    + '<path d="M0 ' + Math.round(h * 0.2) + ' H' + w + '" stroke="#fff" stroke-opacity=".045"/>'
    + '<path d="M0 ' + Math.round(h * 0.84) + ' H' + w + '" stroke="#fff" stroke-opacity=".035"/>'
    + '<path d="M0 ' + Math.round(h * 0.95) + ' L' + w + ' ' + Math.round(h * 0.30) + '" stroke="#fff" stroke-opacity=".028"/>'
    + (wide ? '<circle cx="' + Math.round(w * 0.11) + '" cy="' + Math.round(h * 0.34) + '" r="' + Math.round(h * 0.52) + '" fill="none" stroke="#fff" stroke-opacity=".055"/>' : '')
    + groups
    + dust
    + '<rect width="' + w + '" height="' + h + '" fill="url(#' + id + 's)"/>'
    + '<rect width="' + w + '" height="' + h + '" fill="url(#' + id + 'v)"/>'
    + '</svg>';
  return '<div class="art">' + svg + '</div>';
}

/* =============================================================
   Shadow 资源库 · 交互
   ============================================================= */
(function(){
  'use strict';

  var app = document.getElementById('app');
  var qInput = document.getElementById('q');
  var qClear = document.getElementById('qclear');
  var acctBtn = document.getElementById('acctBtn');
  var acctPop = document.getElementById('acctPop');

  var CHIPS = {
    mod:      ['全部','客户端','服务端','双端','开源许可'],
    shader:   ['全部','写实','柔和','轻量','梦幻'],
    pack:     ['全部','动画','高清','写实','极简','细节'],
    modpack:  [],
    datapack: ['全部','地形','结构','挑战','原版增强']
  };
  var SORTS = [['curated','编辑推荐'],['downloads','最多下载'],['updated','最近更新'],['name','名称排序']];

  var state = { cat:'mod', q:'', chip:'全部', sort:'curated', hero:0, view:'list', demo:'' };
  var detail = null;
  var installTimer = null;
  var savedScroll = 0;
  var hashGuard = false;

  /* ---------- 基础查询 ---------- */
  function matchChip(it, chip){
    if (chip === '全部') return true;
    if (it.cat === 'mod') {
      if (chip === '开源许可') return it.open !== false;
      if (it.env === '双端') return chip === '客户端' || chip === '服务端' || chip === '双端';
      return it.env === chip;
    }
    return it.tags.indexOf(chip) >= 0;
  }
  function sourceLocked(){
    if (state.chip === '全部') return false;
    return state.cat === 'mod' || state.cat === 'shader' || state.cat === 'pack';
  }
  function chipCount(chip){
    var all = catItems(state.cat);
    var lock = chip !== '全部' && (state.cat === 'mod' || state.cat === 'shader' || state.cat === 'pack');
    var n = 0;
    for (var i = 0; i < all.length; i++) {
      if (!matchChip(all[i], chip)) continue;
      if (lock && all[i].source !== 'Modrinth') continue;
      n++;
    }
    return n;
  }
  function visibleItems(){
    var arr = catItems(state.cat);
    var q = state.q.toLowerCase();
    if (q) {
      arr = arr.filter(function(it){
        var hay = (it.cn + ' ' + it.en + ' ' + it.author + ' ' + it.tags.join(' ') + ' ' + it.versions.join(' ')).toLowerCase();
        return hay.indexOf(q) >= 0;
      });
    }
    if (state.chip !== '全部') {
      arr = arr.filter(function(it){ return matchChip(it, state.chip); });
    }
    if (sourceLocked()) {
      arr = arr.filter(function(it){ return it.source === 'Modrinth'; });
    }
    arr = arr.slice();
    if (state.sort === 'downloads') arr.sort(function(a,b){ return b.dl - a.dl; });
    else if (state.sort === 'updated') arr.sort(function(a,b){ return a.upd - b.upd; });
    else if (state.sort === 'name') arr.sort(function(a,b){ return a.cn.localeCompare(b.cn, 'zh'); });
    return arr;
  }
  function sortLabel(){
    for (var i = 0; i < SORTS.length; i++) if (SORTS[i][0] === state.sort) return SORTS[i][1];
    return '编辑推荐';
  }
  function catCount(cat){ return catItems(cat).length; }
  function srcClass(it){
    if (it.source === 'Modrinth') return 'mr';
    if (it.source === 'CurseForge') return 'cf';
    return 'vt';
  }
  function srcBadge(it){
    return '<span class="src-badge ' + srcClass(it) + '"><i class="sq"></i>' + esc(it.source) + '</span>';
  }
  function oneLine(it){
    var s = it.blurb || it.intro || '';
    var i = s.indexOf('。');
    if (i > 10 && i < 48) return s.slice(0, i);
    return s;
  }
  /* ---------- 列表页 ---------- */
  function heroHTML(){
    var cands = heroCandidates(state.cat);
    var idx = state.hero % cands.length;
    var it = cands[idx];
    var cat = CATS[it.cat];
    var n = cands.length;
    var total = String(n).length < 2 ? '0' + n : String(n);
    var cur = String(idx + 1).length < 2 ? '0' + (idx + 1) : String(idx + 1);
    var h = [];
    h.push('<section class="hero" id="hero">');
    h.push('<div class="hero-grid">');
    h.push('<div class="hero-copy">');
    h.push('<div class="hero-kicker"><span class="kline"></span><span class="kicker">编辑推荐 · Editor’s Pick</span><span class="idx">VOL.07 / ' + cur + ' — ' + total + '</span></div>');
    h.push('<h1 class="hero-title">' + esc(it.cn) + '<span>' + esc(it.en) + '</span></h1>');
    h.push('<div class="hero-sub">' + srcBadge(it) + '<span>' + cat.label + ' · ' + esc(it.tags[0]) + '</span><i class="dot"></i><span>' + it.versions.length + ' 个游戏版本</span><i class="dot"></i><span>' + esc(it.loader) + '</span></div>');
    h.push('<p class="hero-desc">' + esc(it.intro) + '</p>');
    h.push('<div class="hero-actions">');
    h.push('<button class="btn primary" data-install="' + it.id + '">' + icon('download', 15) + '安装到 ' + esc(it.versions[0]) + '</button>');
    h.push('<button class="btn ghost" data-open="' + it.id + '">查看详情' + icon('arrow-right', 15) + '</button>');
    h.push('</div>');
    h.push('<div class="hero-stats">');
    h.push('<div class="hs"><b>' + fmtDl(it.dl) + '</b><span>累计下载</span></div>');
    h.push('<div class="hs"><b>' + it.versions.length + '</b><span>适配版本</span></div>');
    h.push('<div class="hs"><b>' + updText(it.upd) + '</b><span>最近更新</span></div>');
    h.push('</div>');
    h.push('</div>');
    h.push('<div class="hero-art">');
    h.push('<div class="plate-back"></div>');
    h.push('<div class="plate">' + scene(it, 640, 300) + '</div>');
    h.push('<div class="fl-tile">' + icon(cat.icon, 30) + '</div>');
    h.push('<div class="fl-badge"><span class="live-dot"></span>' + esc(it.note || '编辑推荐') + '</div>');
    h.push('<div class="hero-pager"><span>' + cur + ' / ' + total + '</span><button class="pg" data-hero-prev aria-label="上一条推荐">' + icon('chevron-left', 13) + '</button><button class="pg" data-hero-next aria-label="下一条推荐">' + icon('chevron-right', 13) + '</button></div>');
    h.push('</div>');
    h.push('</div>');
    h.push('</section>');
    return h.join('');
  }

  function pickCard(it, i){
    var cat = CATS[it.cat];
    var rank = i + 1 < 10 ? '0' + (i + 1) : String(i + 1);
    var h = [];
    h.push('<article class="pick" data-open="' + it.id + '" tabindex="0" role="button" aria-label="' + esc(it.cn) + ' ' + esc(it.en) + '">');
    h.push('<div class="pick-art">' + scene(it, 262, 220) + '<span class="pick-rank">' + rank + '</span>' + '<span class="pick-src src-badge ' + srcClass(it) + '"><i class="sq"></i>' + esc(it.source) + '</span></div>');
    h.push('<div class="pick-body">');
    h.push('<div class="pick-kicker">' + cat.label + ' · ' + esc(it.tags[0]) + '</div>');
    h.push('<h3>' + esc(it.cn) + '<span>' + esc(it.en) + '</span></h3>');
    h.push('<p>' + esc(it.blurb || it.intro) + '</p>');
    h.push('<div class="pick-foot"><span class="f-dl">' + icon('download', 12) + fmtDl(it.dl) + '</span><span class="f-up">' + updText(it.upd) + '</span></div>');
    h.push('</div>');
    h.push('</article>');
    return h.join('');
  }

  function picksHTML(){
    var arr = catItems(state.cat).slice();
    arr.sort(function(a, b){ return b.dl - a.dl; });
    arr = arr.slice(0, 5);
    var h = [];
    h.push('<section class="sec picks-sec">');
    h.push('<div class="sec-head">');
    h.push('<div class="sec-title"><div class="kicker">MOST DOWNLOADED · 累计下载</div><h2 class="sec-h2">下载量最高<em>TOP ' + arr.length + '</em></h2></div>');
    h.push('<div class="sec-tools"><span class="sec-note">按累计下载量排序</span><div class="round-btns">');
    h.push('<button class="rbtn" data-scrollpicks="-1" aria-label="向左滚动">' + icon('chevron-left', 15) + '</button>');
    h.push('<button class="rbtn" data-scrollpicks="1" aria-label="向右滚动">' + icon('chevron-right', 15) + '</button>');
    h.push('</div></div>');
    h.push('</div>');
    h.push('<div class="picks" id="picks">' + arr.map(pickCard).join('') + '</div>');
    h.push('</section>');
    return h.join('');
  }

  function chipsHTML(){
    var chips = CHIPS[state.cat] || [];
    var h = [];
    for (var i = 0; i < chips.length; i++) {
      var c = chips[i];
      var on = state.chip === c ? ' on' : '';
      h.push('<button class="chip' + on + '" data-chip="' + esc(c) + '">' + esc(c) + '<span class="n">' + chipCount(c) + '</span></button>');
    }
    if (sourceLocked()) {
      h.push('<span class="src-lock">' + icon('info', 11) + '筛选结果仅来自 Modrinth</span>');
    }
    return h.join('');
  }
  function sortHTML(){
    var h = [];
    h.push('<div class="sort-wrap">');
    h.push('<button class="sort-btn" data-sort-toggle aria-expanded="false" aria-haspopup="listbox">' + icon('sliders', 13) + '<span id="sortLabel">' + sortLabel() + '</span>' + icon('chevron-down', 13) + '</button>');
    h.push('<div class="menu" id="sortMenu" hidden>');
    for (var i = 0; i < SORTS.length; i++) {
      var on = state.sort === SORTS[i][0] ? ' class="on"' : '';
      h.push('<button data-sort="' + SORTS[i][0] + '"' + on + '><span>' + SORTS[i][1] + '</span>' + icon('check', 13) + '</button>');
    }
    h.push('</div></div>');
    return h.join('');
  }

  function rowCard(it){
    var cat = CATS[it.cat];
    var h = [];
    h.push('<article class="rcard" data-open="' + it.id + '" tabindex="0" role="button" aria-label="' + esc(it.cn) + ' ' + esc(it.en) + '">');
    h.push('<div class="rcard-art">' + scene(it, 120, 120) + '</div>');
    h.push('<div class="rcard-body">');
    h.push('<div class="rcard-title"><h3>' + esc(it.cn) + '</h3><span class="en">' + esc(it.en) + '</span><span class="go">' + icon('arrow-right', 14) + '</span></div>');
    h.push('<div class="rcard-author"><span class="who">适配 ' + esc(it.versions[0]) + '</span><i class="dot"></i><span>' + esc(it.loader) + '</span></div>');
    h.push('<p class="rcard-desc">' + esc(it.blurb || it.intro) + '</p>');
    h.push('<div class="rcard-foot">');
    h.push('<div class="rcard-tags">' + it.tags.slice(0, 2).map(function(t){ return '<span class="tag">' + esc(t) + '</span>'; }).join('') + '</div>');
    h.push('<div class="rcard-meta">' + srcBadge(it) + '<span class="m-dl">' + icon('download', 12) + fmtDl(it.dl) + '</span><span class="sep"></span><span>' + updText(it.upd) + '</span></div>');
    h.push('</div>');
    h.push('</div>');
    h.push('</article>');
    return h.join('');
  }

  function emptyHTML(){
    if (state.demo === 'empty') {
      return '<div class="empty"><span class="eic">' + icon('filter', 20) + '</span><b>没有符合条件的资源</b><span>当前分类下没有命中筛选的资源，接口返回 0 条时展示此状态</span><button class="btn ghost sm" data-state="normal">清除筛选</button></div>';
    }
    return '<div class="empty"><span class="eic">' + icon('search', 20) + '</span><b>没有找到匹配的资源</b><span>换一个关键词，或切换到其他分类看看</span></div>';
  }

  function skeletonHTML(){
    var one = '<div class="skcard"><span class="sk sk-cover"></span><div class="sk-body">'
      + '<span class="sk sk-l1"></span><span class="sk sk-l2"></span><span class="sk sk-l3"></span><span class="sk sk-l4"></span>'
      + '<div class="sk-foot"><span class="sk sk-tag"></span><span class="sk sk-meta"></span></div></div></div>';
    return '<div class="rgrid" aria-busy="true">' + one + one + one + one + '</div>';
  }

  function stateBarHTML(){
    var cur = state.demo || 'normal';
    function b(key, label){
      return '<button data-state="' + key + '"' + (cur === key ? ' class="on"' : '') + '>' + label + '</button>';
    }
    return '<div class="state-bar"><span class="sb-label">设计状态预览</span>'
      + b('normal', '常规') + b('empty', '空结果') + b('skeleton', '骨架屏') + b('timeout', '下载超时')
      + '</div>';
  }

  function listSectionHTML(){
    var cat = CATS[state.cat];
    var items = state.demo === 'empty' ? [] : visibleItems();
    var title = state.demo === 'empty' ? '没有结果' : (state.q ? '搜索结果' : '全部' + cat.label);
    var h = [];
    h.push('<section class="sec list-sec" id="listSec">');
    h.push('<div class="list-head">');
    h.push('<div class="sec-title"><div class="kicker">ALL ' + cat.en + (state.q ? ' · 关键词「' + esc(state.q) + '」' : ' · ' + catCount(state.cat)) + '</div><h2 class="sec-h2">' + title + '<em>' + items.length + ' 项</em></h2></div>');
    if (state.cat === 'datapack') h.push(sortHTML());
    else h.push('<span class="head-note">按编辑推荐排序</span>');
    h.push('</div>');
    if ((CHIPS[state.cat] || []).length) {
      h.push('<div class="chips">' + chipsHTML() + '</div>');
    } else {
      h.push('<div class="chips"><span class="chip-note">' + icon('info', 11) + '整合包暂未开放筛选 · 按来源与热度排序</span></div>');
    }
    if (state.demo === 'skeleton') h.push(skeletonHTML());
    else if (items.length === 0) h.push(emptyHTML());
    else h.push('<div class="rgrid">' + items.map(rowCard).join('') + '</div>');
    h.push('</section>');
    return h.join('');
  }
  function footHTML(){
    return '<footer class="foot"><div class="foot-l"><span class="brand-mini">SHADOW</span><span class="mark"></span>资源库 · 数据来自 Modrinth / CurseForge</div><div class="foot-r">共 ' + ITEMS.length + ' 项资源 · 本周新增 6 · 收录自 2019</div></footer>';
  }

  function renderList(scrollTo){
    detail = null;
    app.innerHTML = heroHTML() + picksHTML() + listSectionHTML() + stateBarHTML() + footHTML();
    updateNav();
    if (scrollTo === 'top') window.scrollTo(0, 0);
    else if (scrollTo === 'restore') {
      var y = savedScroll;
      requestAnimationFrame(function(){ window.scrollTo(0, y); });
    }
  }

  function refreshListSection(){
    var old = document.getElementById('listSec');
    if (!old) return;
    var wrap = document.createElement('div');
    wrap.innerHTML = listSectionHTML();
    old.parentNode.replaceChild(wrap.firstChild, old);
  }

  function refreshHero(){
    var old = document.getElementById('hero');
    if (!old) return;
    var wrap = document.createElement('div');
    wrap.innerHTML = heroHTML();
    old.parentNode.replaceChild(wrap.firstChild, old);
  }

  function updateNav(){
    var cats = document.querySelectorAll('.cat');
    for (var i = 0; i < cats.length; i++) {
      if (cats[i].getAttribute('data-cat') === state.cat) cats[i].classList.add('active');
      else cats[i].classList.remove('active');
    }
  }

  /* ---------- 详情页 ---------- */
  function destFor(kind){
    if (kind === 'shader') return 'shaderpacks/';
    if (kind === 'pack') return 'resourcepacks/';
    if (kind === 'datapack') return '世界存档/datapacks/';
    if (kind === 'modpack') return '由启动器管理';
    return 'mods/';
  }
  function fileExt(it){
    if (it.cat === 'modpack') return '.zip';
    return it.cat === 'mod' ? '.jar' : '.zip';
  }
  function authorAvatar(it){
    var a = it.author.trim();
    return a.length ? a.charAt(0).toUpperCase() : 'S';
  }
  function sourceMark(it){
    if (it.source === 'Modrinth') return 'MODRINTH';
    if (it.source === 'CurseForge') return 'CURSEFORGE';
    return 'VANILLA TWEAKS';
  }
  function clientText(it){
    if (it.cat !== 'mod') return it.cat === 'modpack' ? '客户端整合包' : '客户端资源';
    return it.client === false ? '仅服务端' : '客户端兼容';
  }
  function buildInfo(it, i){
    var bs = buildsFor(it);
    var idx = Math.min(Math.max(i, 0), bs.length - 1);
    var b = bs[idx];
    var isBeta = idx === 2;
    var ratio = idx === 0 ? 0.21 : (idx === 1 ? 0.11 : 0.05);
    return {
      v: b.v,
      size: b.size,
      type: isBeta ? 'beta' : 'release',
      typeText: isBeta ? '测试版' : '正式版',
      date: dayStr(it.upd + idx * 26),
      dl: Math.round(it.dl * ratio)
    };
  }
  function currentBuild(){ return buildInfo(detail.it, detail.bi); }

  function renderDetail(){
    var it = detail.it;
    var cat = CATS[it.cat];
    var bs = buildsFor(it);
    var b0 = buildInfo(it, 0);
    var deps = depsFor(it);
    var shots = shotsFor(it);
    var h = [];

    h.push('<div class="detail">');

    h.push('<div class="dbar">');
    h.push('<button class="back" data-back>' + icon('arrow-left', 15) + '返回资源库</button>');
    h.push('<div class="crumbs"><span>资源库</span><span class="sep">/</span><span>' + cat.label + '</span><span class="sep">/</span><span>' + esc(it.tags[0]) + '</span><span class="sep">/</span><span class="cur">' + esc(it.cn) + ' ' + esc(it.en) + '</span></div>');
    h.push('<div class="dbar-tools">');
    h.push('<button class="icon-btn" data-share>' + icon('link', 15) + '<span>复制链接</span></button>');
    h.push('<button class="icon-btn" data-more aria-label="更多操作">' + icon('more-horizontal', 16) + '</button>');
    h.push('</div></div>');

    h.push('<div class="dhead">');
    h.push('<div class="dcover">');
    h.push(scene(it, 1240, 280, { v:'cover' }));
    h.push('<div class="dcover-shade"></div>');
    h.push('<div class="dcover-badges"><span class="dbadge">' + cat.label + ' · ' + esc(it.tags[0]) + '</span><span class="dbadge"><span class="okdot"></span>' + esc(it.versions[0]) + ' 已适配</span><span class="dbadge">' + esc(it.loader) + '</span></div>');
    h.push('<div class="dcover-icon">' + icon(cat.icon, 30) + '</div>');
    h.push('<div class="dcover-main"><h1>' + esc(it.cn) + '<span>' + esc(it.en) + '</span></h1>');
    h.push('<div class="dcover-sub">' + srcBadge(it) + '<span>' + esc(it.license) + '</span><i class="dot"></i><span>' + clientText(it) + '</span><i class="dot"></i><span>更新于 ' + updText(it.upd) + ' · ' + b0.date + '</span></div></div>');
    h.push('</div>');

    h.push('<div class="statbar">');
    h.push('<div class="stat"><span>累计下载</span><b>' + fmtNum(it.dl) + '</b></div>');
    h.push('<div class="stat"><span>适配版本</span><b>' + it.versions.length + ' 个</b></div>');
    h.push('<div class="stat"><span>加载器</span><b>' + esc(it.loader) + '</b></div>');
    h.push('<div class="stat"><span>最新文件</span><b id="statSize">' + esc(b0.size) + '</b></div>');
    h.push('<div class="stat"><span>最近更新</span><b>' + updText(it.upd) + '</b></div>');
    h.push('<div class="statbar-right"><span class="pulse"></span>数据源 ' + esc(it.source) + '<button class="round" data-sync aria-label="刷新元数据">' + icon('refresh-cw', 13) + '</button></div>');
    h.push('</div></div>');

    h.push('<div class="dnote">' + icon('info', 12) + '带「待接口」标记的区块需要后端新增项目详情接口；其余字段来自现有资源 / 版本接口</div>');

    h.push('<div class="dbody">');
    h.push('<div class="dmain">');

    h.push('<article class="block">');
    h.push('<div class="block-head"><div class="kicker">ABOUT</div><h2>关于 ' + esc(it.cn) + '<em>' + esc(it.en) + '</em><span class="api-tag">待接口</span></h2></div>');
    h.push('<div class="api-note">' + icon('info', 12) + '<span>当前接口只有一句话 desc；以下分节长文为版式示意，需项目详情接口提供正文 Markdown。</span></div>');
    h.push('<div class="prose">');
    h.push('<p class="lead">' + esc(it.intro) + '</p>');
    h.push('<p>' + esc(it.p2 || KIND_P2[it.kind]) + '</p>');
    h.push('<p>' + esc(it.p3 || KIND_P3[it.kind]) + '</p>');
    h.push('</div>');
    h.push('<blockquote class="quote"><p>' + esc(KIND_QUOTE[it.kind]) + '</p><cite>—— 编辑手记 · 第 07 期</cite></blockquote>');
    h.push('</article>');

    h.push('<article class="block">');
    h.push('<div class="block-head"><div class="kicker">GALLERY</div><h2>画面与实装<em>' + shots.length + ' 张</em><span class="api-tag">待接口</span></h2></div>');
    h.push('<div class="api-note">' + icon('info', 12) + '<span>图集需要详情接口的 screenshots 字段，当前接口不返回截图。</span></div>');
    h.push('<div class="gallery">');
    h.push('<figure>' + '<div class="g-art">' + scene(it, 300, 169, { v:'ga' }) + '</div>' + '<figcaption><span>' + esc(shots[0]) + '</span><em>01</em></figcaption></figure>');
    var hue2 = [it.hue[1], it.hue[0]];
    h.push('<figure>' + '<div class="g-art">' + scene(it, 300, 169, { v:'gb', hue:hue2, motif:altMotif(it.motif) }) + '</div>' + '<figcaption><span>' + esc(shots[1]) + '</span><em>02</em></figcaption></figure>');
    h.push('</div>');
    h.push('</article>');

    h.push('<article class="block">');
    h.push('<div class="block-head"><div class="kicker">REQUIREMENTS</div><h2>依赖与兼容<em>' + deps.length + ' 项前置</em><span class="api-tag">待接口</span></h2></div>');
    h.push('<div class="api-note">' + icon('info', 12) + '<span>兼容版本来自 versions（真实字段）；前置依赖需版本接口补充 dependencies 字段。</span></div>');
    h.push('<div class="deps">');
    for (var d = 0; d < deps.length; d++) {
      var dep = deps[d];
      var cls = dep.req === '必需' || dep.req === '建议' ? 'req' : 'opt';
      var dic = dep.req === '必需' ? 'package' : (dep.req === '建议' ? 'sliders' : 'info');
      h.push('<div class="dep"><span class="dep-ic">' + icon(dic, 14) + '</span><div class="dep-info"><b>' + esc(dep.n) + '</b><span>' + esc(dep.v) + '</span></div><span class="dep-tag ' + cls + '">' + esc(dep.req) + '</span><span class="ext">' + icon('arrow-up-right', 13) + '</span></div>');
    }
    h.push('</div>');
    h.push('<div class="compat"><span class="compat-title">已适配的游戏版本（来自 versions 字段）</span><div class="compat-list">');
    for (var v = 0; v < it.versions.length; v++) {
      var okv = v < 4;
      h.push('<span class="ctag ' + (okv ? 'ok' : 'no') + '">' + icon(okv ? 'check' : 'x', 11) + esc(it.versions[v]) + '</span>');
    }
    h.push('</div></div>');
    h.push('</article>');

    h.push('<article class="block">');
    h.push('<div class="block-head"><div class="kicker">CHANGELOG</div><h2>版本时间线<em>最近 ' + bs.length + ' 个文件</em></h2></div>');
    h.push('<div class="api-note">' + icon('info', 12) + '<span>版本号、发布时间、类型、大小、下载量均来自版本接口；更新说明文本需后端补充 changelog 字段。</span></div>');
    h.push('<div class="tl">');
    for (var c = 0; c < bs.length; c++) {
      var bi = buildInfo(it, c);
      h.push('<div class="tl-item' + (c === 0 ? ' now' : '') + '">');
      h.push('<div class="tl-head"><span class="tl-v">' + esc(bi.v) + '</span><span class="tl-d">' + bi.date + '</span><span class="tl-badge">' + (c === 0 ? '最新 · ' : '') + bi.typeText + '</span></div>');
      h.push('<div class="tl-meta"><span>' + bi.size + '</span><i class="dot"></i><span>下载 ' + fmtDl(bi.dl) + '</span><i class="dot"></i><span>' + esc(it.versions[0]) + '</span></div>');
      if (c === 0) h.push('<p class="tl-note">更新说明：需后端在版本接口中补充 changelog 字段</p>');
      h.push('</div>');
    }
    h.push('</div>');
    h.push('<button class="more-link" data-more-log>查看完整版本历史' + icon('arrow-right', 12) + '</button>');
    h.push('</article>');

    h.push('</div>');

    h.push('<aside class="dside"><div class="sticky">');

    h.push('<div class="icard">');
    h.push('<div class="icard-head"><div><div class="kicker">INSTALL</div><h3>安装</h3></div><span class="badge-src">' + icon('shield-check', 12) + esc(it.source) + '</span></div>');
    h.push('<div class="icard-body">');
    h.push('<div class="field"><div class="field-label">游戏版本<em>' + it.versions.length + ' 个可用版本</em></div><div class="select-wrap">');
    h.push('<button class="select" id="mcBtn" data-mc-toggle aria-expanded="false" aria-haspopup="listbox"><span id="mcLabel">' + esc(detail.mc) + '</span><span class="mc-tag">最新</span>' + icon('chevron-down', 14) + '</button>');
    h.push('<div class="menu left" id="mcMenu" hidden>');
    for (var m = 0; m < it.versions.length; m++) {
      var onm = detail.mc === it.versions[m] ? ' class="on"' : '';
      h.push('<button data-mc="' + esc(it.versions[m]) + '"' + onm + '><span>' + esc(it.versions[m]) + '</span>' + icon('check', 13) + '</button>');
    }
    h.push('</div></div></div>');

    h.push('<div class="field"><div class="field-label">文件版本<em id="buildHint">' + esc(b0.v) + ' · ' + b0.date.slice(5) + '</em></div><div class="pills" id="pills">');
    for (var b = 0; b < bs.length; b++) {
      h.push('<button class="pill' + (b === 0 ? ' on' : '') + '" data-build="' + b + '">' + esc(bs[b].v) + '</button>');
    }
    h.push('</div></div>');

    h.push('<div class="vmeta-line"><span class="vm-type" id="vmType">' + b0.typeText + '</span><span class="dot"></span><span id="vmDate">' + b0.date + '</span><span class="dot"></span><span>下载 <b id="vmDl">' + fmtDl(b0.dl) + '</b></span><span class="vm-size" id="vmSize">' + b0.size + '</span></div>');

    h.push('<div class="inst-area" id="instArea">' + instActionsHTML() + '</div>');

    h.push('<dl class="kv">');
    h.push('<div><dt>加载器</dt><dd>' + esc(it.loader) + '</dd></div>');
    h.push('<div><dt>安装位置</dt><dd>' + destFor(it.kind) + '</dd></div>');
    h.push('</dl>');

    h.push('<div class="link-row"><button class="link-btn" data-manual>手动下载 ' + fileExt(it) + icon('external-link', 11) + '</button><button class="link-btn" data-folder>打开目录' + icon('arrow-up-right', 11) + '</button></div>');
    h.push('<div class="demo-row"><span>状态演示 · 未安装 / 下载中 / 失败</span><button data-demo-fail>失败态</button></div>');
    h.push('</div></div>');

    h.push('<div class="side-card"><div class="sc-head"><span>AUTHOR</span><span class="api-tag">待接口</span></div>');
    h.push('<div class="author-empty"><span class="ae-ic">' + icon('user', 15) + '</span><div><b>作者信息不可用</b><span>当前接口不返回 author 字段</span></div></div>');
    h.push('<p class="sc-note">作者、项目数与关注数依赖项目详情接口；此处保留版式位，接入后再填充。</p>');
    h.push('</div>');

    h.push('<div class="side-card"><div class="sc-head"><span>SOURCE</span><a href="#" data-source>在 ' + esc(it.source) + ' 打开</a></div>');
    h.push('<div class="kv-mini"><span>来源</span><b>' + esc(sourceMark(it)) + '</b></div>');
    h.push('<div class="kv-mini"><span>许可证</span><b>' + esc(it.license) + '</b></div>');
    h.push('<div class="kv-mini"><span>加载器</span><b>' + esc(it.loader) + '</b></div>');
    h.push('<div class="kv-mini"><span>客户端兼容</span><b>' + (it.cat === 'mod' ? (it.client === false ? '否' : '是') : '—') + '</b></div>');
    h.push('<div class="kv-mini"><span>最后更新</span><b>' + dayStr(it.upd) + '</b></div>');
    h.push('<div class="src-foot"><span class="lic">' + icon('shield-check', 12) + '字段来自现有接口</span><a href="#" data-source>查看源页' + icon('external-link', 11) + '</a></div>');
    h.push('</div>');

    h.push('</div></aside>');
    h.push('</div>');

    var more = catItems(it.cat).filter(function(x){ return x.id !== it.id; }).slice(0, 4);
    h.push('<section class="more"><div class="sec-head"><div class="sec-title"><div class="kicker">MORE LIKE THIS</div><h2 class="sec-h2">更多同类<em>' + cat.label + '</em></h2></div><div class="sec-tools"><button class="sort-btn" data-back-cat>浏览全部 ' + cat.label + icon('arrow-right', 12) + '</button></div></div>');
    h.push('<div class="more-grid">');
    for (var k = 0; k < more.length; k++) {
      var mi = more[k];
      h.push('<article class="mcard" data-open="' + mi.id + '" tabindex="0" role="button"><div class="m-art">' + scene(mi, 100, 100, { v:'m' }) + '</div><div class="m-body"><h4>' + esc(mi.cn) + '</h4><span class="en">' + esc(mi.en) + '</span><div class="m-meta">' + srcBadge(mi) + icon('download', 11) + fmtDl(mi.dl) + '<span class="dot"></span>' + updText(mi.upd) + '</div></div></article>');
    }
    h.push('</div></section>');
    h.push(footHTML());
    h.push('</div>');

    app.innerHTML = h.join('');
    window.scrollTo(0, 0);
    var catEls = document.querySelectorAll('.cat');
    for (var n = 0; n < catEls.length; n++) catEls[n].classList.toggle('active', catEls[n].getAttribute('data-cat') === it.cat);
  }

  function instActionsHTML(){
    if (!detail) return '';
    var b = currentBuild();
    if (detail.phase === 'running') {
      return '<div class="prog"><div class="prog-top"><span>正在下载 · <b id="pct">0%</b></span><span class="spd" id="spd">2.1 MB/s</span></div>'
        + '<div class="bar"><i id="barFill" style="width:0%"></i></div>'
        + '<div class="prog-foot"><span id="bytes">0.0 / ' + sizeMb(b.size).toFixed(1) + ' MB</span><button data-cancel>取消下载</button></div></div>';
    }
    if (detail.phase === 'failed') {
      return '<div class="fail-box"><span class="fik">' + icon('alert-triangle', 14) + '</span><div><b>下载失败</b><span>连接在 68% 处中断，临时文件已清理 · NET_521</span><div class="facts"><button class="retry" data-retry>重试</button><button data-log>查看日志</button></div></div></div>';
    }
    if (detail.phase === 'timeout') {
      return '<div class="fail-box timeout"><span class="fik">' + icon('clock', 14) + '</span><div><b>下载超时</b><span>9 秒内没有收到任何进度更新，已自动中止，可重试</span><div class="facts"><button class="retry" data-retry>重试</button><button data-log>查看日志</button></div></div></div>';
    }
    if (detail.phase === 'done') {
      return '<div class="done-box pending"><span class="dok">' + icon('check', 14) + '</span><div><b>下载完成<span class="pend-tag">已安装状态待后端</span></b><span>' + b.size + ' 已写入 ' + destFor(detail.it.kind) + '</span></div><button data-again>重新下载</button></div>';
    }
    return '<button class="btn primary block" data-install-now>' + icon('download', 15) + '下载并安装</button>';
  }

  function paintProgress(){
    if (!detail) return;
    var b = currentBuild();
    var mb = sizeMb(b.size);
    var pctEl = document.getElementById('pct');
    if (pctEl) pctEl.textContent = Math.round(detail.pct) + '%';
    var fill = document.getElementById('barFill');
    if (fill) fill.style.width = detail.pct.toFixed(1) + '%';
    var bytes = document.getElementById('bytes');
    if (bytes) bytes.textContent = (mb * detail.pct / 100).toFixed(1) + ' / ' + mb.toFixed(1) + ' MB';
    var spd = document.getElementById('spd');
    if (spd) spd.textContent = (1.6 + Math.random() * 1.6).toFixed(1) + ' MB/s';
  }

  function beginInstall(){
    if (!detail || detail.phase === 'running') return;
    detail.phase = 'running';
    detail.pct = 0;
    var area = document.getElementById('instArea');
    if (area) area.innerHTML = instActionsHTML();
    paintProgress();
    toast('开始下载 ' + detail.it.cn + ' ' + currentBuild().v, 'ok');
    clearInterval(installTimer);
    installTimer = setInterval(function(){
      if (!detail || detail.phase !== 'running') { clearInterval(installTimer); return; }
      detail.pct = Math.min(100, detail.pct + 1.4 + Math.random() * 2.8);
      paintProgress();
      if (detail.pct >= 100) {
        clearInterval(installTimer);
        detail.phase = 'done';
        var a = document.getElementById('instArea');
        if (a) a.innerHTML = instActionsHTML();
        toast(detail.it.cn + ' 下载完成；已安装状态需后端提供', 'ok');
      }
    }, 110);
  }

  function cancelInstall(silent){
    clearInterval(installTimer);
    if (detail) {
      detail.phase = 'idle';
      detail.pct = 0;
      var area = document.getElementById('instArea');
      if (area) area.innerHTML = instActionsHTML();
    }
    if (!silent) toast('已取消下载', 'warn');
  }

  function syncBuildUI(){
    if (!detail) return;
    var b = currentBuild();
    var sizeEl = document.getElementById('sizeVal');
    if (sizeEl) sizeEl.textContent = b.size;
    var statSize = document.getElementById('statSize');
    if (statSize) statSize.textContent = b.size;
    var hint = document.getElementById('buildHint');
    if (hint) hint.textContent = b.v + ' · ' + b.date.slice(5);
    var vmType = document.getElementById('vmType');
    if (vmType) vmType.textContent = b.typeText;
    var vmDate = document.getElementById('vmDate');
    if (vmDate) vmDate.textContent = b.date;
    var vmSize = document.getElementById('vmSize');
    if (vmSize) vmSize.textContent = b.size;
    var vmDl = document.getElementById('vmDl');
    if (vmDl) vmDl.textContent = fmtDl(b.dl);
    var pills = document.querySelectorAll('#pills .pill');
    for (var i = 0; i < pills.length; i++) {
      if (i === detail.bi) pills[i].classList.add('on');
      else pills[i].classList.remove('on');
    }
    var menu = document.getElementById('mcMenu');
    if (menu) menu.hidden = true;
    var btn = document.getElementById('mcBtn');
    if (btn) btn.setAttribute('aria-expanded', 'false');
    var opts = document.querySelectorAll('#mcMenu button');
    for (var j = 0; j < opts.length; j++) {
      if (opts[j].getAttribute('data-mc') === detail.mc) opts[j].classList.add('on');
      else opts[j].classList.remove('on');
    }
    if (detail.phase === 'idle') {
      var area = document.getElementById('instArea');
      if (area) area.innerHTML = instActionsHTML();
    }
  }

  function selectMc(mc){
    if (!detail) return;
    if (detail.phase === 'running') { toast('下载进行中，无法切换版本', 'warn'); return; }
    if (detail.phase === 'done' || detail.phase === 'failed') { detail.phase = 'idle'; }
    detail.mc = mc;
    var label = document.getElementById('mcLabel');
    if (label) label.textContent = mc;
    var tag = document.querySelector('#mcBtn .mc-tag');
    if (tag) tag.textContent = detail.it.versions[0] === mc ? '最新' : '适配';
    syncBuildUI();
    toast('已切换到游戏版本 ' + mc, 'ok');
  }

  function selectBuild(i){
    if (!detail) return;
    if (detail.phase === 'running') { toast('下载进行中，无法切换文件版本', 'warn'); return; }
    if (detail.phase === 'done' || detail.phase === 'failed') { detail.phase = 'idle'; }
    detail.bi = i;
    syncBuildUI();
  }

  /* ---------- 路由 ---------- */
  function openItem(id){
    var it = itemById(id);
    if (!it) return;
    if (state.view === 'list') savedScroll = window.scrollY;
    state.view = 'detail';
    state.cat = it.cat;
    detail = { it: it, mc: it.versions[0], bi: 0, phase: 'idle', pct: 0 };
    clearInterval(installTimer);
    renderDetail();
    setHash('#/item/' + id);
  }

  function backToList(restore, noHash){
    if (detail && detail.phase === 'running') cancelInstall(true);
    detail = null;
    state.view = 'list';
    renderList(restore === false ? 'top' : 'restore');
    if (!noHash) setHash('#/list');
  }

  function setHash(h){
    if (location.hash === h) return;
    hashGuard = true;
    try { location.hash = h; } catch (err) {}
    setTimeout(function(){ hashGuard = false; }, 40);
  }

  /* ---------- 提示 ---------- */
  function toast(msg, kind){
    var wrap = document.getElementById('toasts');
    if (!wrap) return;
    var d = document.createElement('div');
    d.className = 'toast ' + (kind || '');
    var ic = kind === 'ok' ? 'check-circle' : (kind === 'warn' ? 'alert-triangle' : 'info');
    d.innerHTML = icon(ic, 15) + '<span>' + esc(msg) + '</span>';
    wrap.appendChild(d);
    setTimeout(function(){
      d.classList.add('out');
      setTimeout(function(){ if (d.parentNode) d.parentNode.removeChild(d); }, 260);
    }, 2600);
  }

  function closeMenus(){
    var ms = document.querySelectorAll('.menu');
    for (var i = 0; i < ms.length; i++) ms[i].hidden = true;
    var btns = document.querySelectorAll('[data-mc-toggle],[data-sort-toggle]');
    for (var j = 0; j < btns.length; j++) btns[j].setAttribute('aria-expanded', 'false');
    if (acctPop) acctPop.hidden = true;
    if (acctBtn) acctBtn.setAttribute('aria-expanded', 'false');
  }

  /* ---------- 事件 ---------- */
  document.addEventListener('click', function(e){
    var t = e.target;
    if (!t.closest) return;
    var el;

    if (!t.closest('.menu') && !t.closest('[data-mc-toggle]') && !t.closest('[data-sort-toggle]') && !t.closest('#acctBtn')) {
      closeMenus();
    }

    if ((el = t.closest('[data-cat]'))) {
      var cat = el.getAttribute('data-cat');
      if (cat !== state.cat || state.view !== 'list') {
        state.cat = cat;
        state.chip = '全部';
        state.sort = 'curated';
        state.hero = 0;
        state.view = 'list';
        renderList('top');
        setHash('#/list');
      }
      return;
    }

    if ((el = t.closest('[data-home]'))) {
      e.preventDefault();
      if (state.view === 'detail') backToList(true);
      else window.scrollTo(0, 0);
      return;
    }

    if ((el = t.closest('[data-back]'))) {
      backToList(true);
      return;
    }

    if ((el = t.closest('[data-hero-next]'))) {
      var cands = heroCandidates(state.cat);
      state.hero = (state.hero + 1) % cands.length;
      refreshHero();
      return;
    }
    if ((el = t.closest('[data-hero-prev]'))) {
      var cands2 = heroCandidates(state.cat);
      state.hero = (state.hero - 1 + cands2.length) % cands2.length;
      refreshHero();
      return;
    }

    if ((el = t.closest('[data-scrollpicks]'))) {
      var box = document.getElementById('picks');
      if (box) box.scrollBy({ left: parseInt(el.getAttribute('data-scrollpicks'), 10) * 440, behavior: 'smooth' });
      return;
    }

    if ((el = t.closest('[data-chip]'))) {
      state.chip = el.getAttribute('data-chip');
      refreshListSection();
      return;
    }

    if ((el = t.closest('[data-sort-toggle]'))) {
      var sm = document.getElementById('sortMenu');
      if (sm) {
        var open = sm.hidden;
        closeMenus();
        sm.hidden = !open;
        el.setAttribute('aria-expanded', open ? 'true' : 'false');
      }
      return;
    }

    if ((el = t.closest('[data-sort]'))) {
      state.sort = el.getAttribute('data-sort');
      refreshListSection();
      toast('排序：' + sortLabel(), 'ok');
      return;
    }

    if ((el = t.closest('[data-mc-toggle]'))) {
      if (!detail) return;
      if (detail.phase === 'running') { toast('安装进行中，无法切换版本', 'warn'); return; }
      var mm = document.getElementById('mcMenu');
      if (mm) {
        var openm = mm.hidden;
        mm.hidden = !openm;
        el.setAttribute('aria-expanded', openm ? 'true' : 'false');
      }
      return;
    }

    if ((el = t.closest('[data-mc]'))) {
      selectMc(el.getAttribute('data-mc'));
      return;
    }

    if ((el = t.closest('[data-build]'))) {
      selectBuild(parseInt(el.getAttribute('data-build'), 10));
      return;
    }

    if ((el = t.closest('[data-state]'))) {
      var s = el.getAttribute('data-state');
      if (s === 'timeout') {
        openItem('sodium');
        setTimeout(function(){
          if (!detail) return;
          detail.phase = 'timeout';
          var a = document.getElementById('instArea');
          if (a) a.innerHTML = instActionsHTML();
        }, 80);
        return;
      }
      state.demo = s === 'normal' ? '' : s;
      detail = null;
      state.view = 'list';
      renderList();
      var sec = document.getElementById('listSec');
      if (sec) sec.scrollIntoView({ block: 'start' });
      return;
    }

    if ((el = t.closest('[data-install-now]'))) {
      beginInstall();
      return;
    }
    if ((el = t.closest('[data-cancel]'))) {
      cancelInstall(false);
      return;
    }
    if ((el = t.closest('[data-again]'))) {
      detail.phase = 'idle';
      beginInstall();
      return;
    }

    if ((el = t.closest('[data-demo-fail]'))) {
      if (!detail) return;
      detail.phase = 'failed';
      detail.pct = 0;
      var fa = document.getElementById('instArea');
      if (fa) fa.innerHTML = instActionsHTML();
      toast('失败态预览：NET_521', 'warn');
      return;
    }
    if ((el = t.closest('[data-retry]'))) {
      beginInstall();
      return;
    }
    if ((el = t.closest('[data-log]'))) {
      toast('安装日志已保存到 logs/shadow_launcher.log', 'ok');
      return;
    }

    if ((el = t.closest('[data-install]'))) {
      var iid = el.getAttribute('data-install');
      openItem(iid);
      setTimeout(function(){ beginInstall(); }, 420);
      return;
    }

    if ((el = t.closest('[data-open]'))) {
      openItem(el.getAttribute('data-open'));
      return;
    }

    if ((el = t.closest('[data-fav]'))) {
      el.classList.toggle('on');
      var on = el.classList.contains('on');
      var lbl = el.querySelector('span');
      if (lbl) lbl.textContent = on ? '已收藏' : '收藏';
      toast(on ? '已加入收藏' : '已取消收藏', 'ok');
      return;
    }

    if ((el = t.closest('[data-share]'))) {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(location.href).catch(function(){});
      }
      toast('资源链接已复制', 'ok');
      return;
    }

    if ((el = t.closest('[data-follow]'))) {
      var following = el.classList.contains('on');
      el.classList.toggle('on');
      var sp = el.querySelector('span');
      if (sp) sp.textContent = following ? '关注作者' : '已关注';
      toast(following ? '已取消关注' : '已关注 ' + (detail ? detail.it.author : ''), 'ok');
      return;
    }

    if (t.closest('[data-manual]')) {
      if (detail) toast('开始下载 ' + detail.it.en + ' ' + currentBuild().v + ' ' + fileExt(detail.it), 'ok');
      return;
    }
    if (t.closest('[data-folder]')) {
      if (detail) toast('正在打开 ' + destFor(detail.it.kind), 'ok');
      return;
    }
    if (t.closest('[data-source]')) {
      e.preventDefault();
      if (detail) toast('正在浏览器中打开 ' + detail.it.source + ' 项目页', 'ok');
      return;
    }
    if (t.closest('[data-more-log]')) {
      toast('完整版本历史共 42 个版本', 'ok');
      return;
    }
    if (t.closest('[data-sync]')) {
      toast('元数据已是最新', 'ok');
      return;
    }
    if (t.closest('[data-back-cat]')) {
      backToList(false);
      return;
    }
    if (t.closest('[data-author]')) {
      e.preventDefault();
      toast('作者主页待接入社区接口', 'warn');
      return;
    }

    if ((el = t.closest('[data-acct]')) || t.closest('#acctBtn')) {
      var wasOpen = acctPop && !acctPop.hidden;
      closeMenus();
      if (acctPop && !wasOpen) {
        acctPop.hidden = false;
        if (acctBtn) acctBtn.setAttribute('aria-expanded', 'true');
      }
      return;
    }

    if ((el = t.closest('#qclear'))) {
      qInput.value = '';
      state.q = '';
      qClear.classList.remove('show');
      refreshListSection();
      qInput.focus();
      return;
    }
  });

  qInput.addEventListener('input', function(){
    state.q = this.value.trim();
    if (this.value.length > 0) qClear.classList.add('show');
    else qClear.classList.remove('show');
    if (state.view === 'list') refreshListSection();
  });

  document.addEventListener('keydown', function(e){
    if (e.key === 'Escape') {
      var anyMenu = document.querySelector('.menu:not([hidden])');
      if (anyMenu || (acctPop && !acctPop.hidden)) { closeMenus(); return; }
      if (state.view === 'detail') { backToList(true); return; }
    }
    if (e.key === '/' && document.activeElement !== qInput) {
      e.preventDefault();
      qInput.focus();
      return;
    }
    if ((e.key === 'Enter' || e.key === ' ') && e.target && e.target.closest && e.target.closest('.pick,.rcard,.mcard')) {
      e.preventDefault();
      var card = e.target.closest('[data-open]');
      if (card) openItem(card.getAttribute('data-open'));
    }
  });

  window.addEventListener('hashchange', function(){
    if (hashGuard) return;
    var h = location.hash || '';
    if (h.indexOf('#/item/') === 0) {
      var id = h.slice(7);
      if (id && (!detail || detail.it.id !== id)) openItem(id);
    } else if (state.view === 'detail') {
      backToList(true, true);
    }
  });

  /* ---------- 启动 ---------- */
  function boot(){
    var h = location.hash || '';
    if (h.indexOf('#/item/') === 0) {
      var id = h.slice(7);
      if (itemById(id)) { openItem(id); return; }
    }
    renderList();
  }
  boot();
})();

