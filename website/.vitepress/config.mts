import { defineConfig } from 'vitepress'

export default defineConfig({
  base: '/portscan/',
  lang: 'zh-CN',
  title: 'PortMaster',
  description: 'macOS 上的 Windows 任务管理器：进程、CPU、内存与端口占用，一个窗口看清。',
  head: [
    ['link', { rel: 'icon', type: 'image/png', href: '/portscan/logo.png' }],
    ['meta', { property: 'og:title', content: 'PortMaster — macOS 上的 Windows 任务管理器' }],
    ['meta', { property: 'og:description', content: '进程、CPU、内存与端口占用，一个窗口看清。纯本地、只读、不联网。' }],
  ],
  themeConfig: {
    logo: '/logo.png',
    nav: [
      { text: '首页', link: '/' },
      { text: '使用指南', link: '/guide' },
      { text: 'GitHub', link: 'https://github.com/chendpoc/portscan' },
    ],
    sidebar: [
      { text: '使用指南', link: '/guide' },
    ],
    socialLinks: [
      { icon: 'github', link: 'https://github.com/chendpoc/portscan' },
    ],
    footer: {
      message: '纯本地运行 · 只读采集 · 不上传任何数据',
      copyright: 'PortMaster — 用 SwiftUI 为 macOS 打造',
    },
    outline: { label: '本页目录' },
    docFooter: { prev: '上一页', next: '下一页' },
    darkModeSwitchLabel: '外观',
    returnToTopLabel: '回到顶部',
  },
})
