# luatos-lib-onenetcors

OneNet平台, 单频的RTK的免费MQTT播发

主要是演示一下如何对接, 最重要的是, 必须有支持RTK的硬件

**非官方库,如有任意疑问或建议,请报issue,随缘更新**

## 介绍

本客户端基于socket库, 兼容所有LuatOS平台, 只要该平台实现mqtt库均可

## 安装

本协议库使用纯lua编写, 所以不需要编译, 直接将源码拷贝到项目即可

## 使用

1. 这RTK服务后续是否收费, 单纯看OneNET了, 能用一天算一天咯
2. 注册OneNET平台, 创建项目, 获取设备ID和密码
3. 修改demo里的ID和密码, 下载到设备运行即可
4. 默认uart id是1, 波特率是115200, 一定要是支持RTK的GNSS模块才能用,不然没有意义

## 变更日志

[changelog](changelog.md)

## LIcense

[MIT License](https://opensource.org/licenses/MIT)
