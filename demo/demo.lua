
local demo = {}

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "onenetdemo"
VERSION = "1.0.0"

--[[
本demo需要mqtt库, 大部分能联网的设备都具有这个库
mqtt也是内置库, 无需require

本demo演示的是 OneNet Studio, 注意区分
https://open.iot.10086.cn/studio/summary
https://open.iot.10086.cn/doc/v5/develop/detail/iot_platform
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")


-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

-- 根据自己的设备修改以下参数
----------------------------------------------
-- OneNet Studio
mqtt_host = "mqtts.heclouds.com"
mqtt_port = 1883
mqtt_isssl = false
local pid = "Ck2AF9QD2K" -- 产品id
local device = "RTK000001" -- 设备名称, 按需设置, 如果是Cat.1系列通常用mobile.imei()
local device_secret = "eHIxeFBWWVZ0eGdNenRGeHpNNU8weVVRQmdoYWM1SmY=" -- 设备密钥
client_id, user_name, password = iotauth.onenet(pid, device, device_secret)

-- 下面是常用的topic, 完整topic可参考 https://open.iot.10086.cn/doc/v5/develop/detail/639
pub_topic = "$sys/" .. pid .. "/" .. device .. "/thing/property/post"
sub_topic = "$sys/" .. pid .. "/" .. device .. "/thing/property/set"
-- pub_custome = "$sys/" .. pid .. "/" .. device .. "/custome/up"
-- pub_custome_reply = "$sys/" .. pid .. "/" .. device .. "/custome/up_reply"
-- sub_custome = "$sys/" .. pid .. "/" .. device .. "/custome/down/+"
-- sub_custome_reply = "$sys/" .. pid .. "/" .. device .. "/custome/down_reply/"
pub_event = "$sys/" .. pid .. "/" .. device .. "/thing/event/post"
pub_event_reply = "$sys/" .. pid .. "/" .. device .. "/thing/event/post/reply"

-- $sys/{pid}/{device-name}/thing/service/{identifier}/invoke
service_invoke = "$sys/" .. pid .. "/" .. device .. "/thing/service/$OneNET_LBS_HPP_DF/invoke"
service_reply = "$sys/" .. pid .. "/" .. device .. "/thing/service/$OneNET_LBS_HPP_DF/invoke_reply"
------------------------------------------------

local mqttc = nil

local gnss_uart_id = 1

local function gnss_write(data)
    -- log.info("ntrip", "write")
    uart.tx(gnss_uart_id, data)
end

sys.taskInit(function ()
    uart.setup(gnss_uart_id, 115200)
    uart.on(gnss_uart_id, "receive", function(id, len)
        local s = ""
        repeat
            s = uart.read(id, 1024)
            if #s > 0 then
                local rmc = s:find("$GNRMC,")
                if rmc and s:find("\r\n", rmc) then
                    log.info("uart", s:sub(rmc, s:find("\r\n", rmc) - 1))
                end
                local gga = s:find("$GNGGA,")
                if gga and s:find("\r\n", gga) then
                    log.info("uart", s:sub(gga, s:find("\r\n", gga) - 1))
                    if mqttc and mqttc:ready() then
                        local g = s:sub(gga, s:find("\r\n", gga) + 1)
                        local tmp = {
                            id = "123",
                            version= "1.0",
                            params = {}
                        }
                        tmp["params"]["$OneNET_LBS_HPP"] = {value={data={gga=g,tag=0,coord=2,src=104}}}
                        local payload = json.encode(tmp)
                        -- log.info("待上行的GGA数据", payload)
                        mqttc:publish(pub_event, payload, 1)
                    end
                end
            end
            if #s == len then
                break
            end
        until s == ""
    end)
end)

function on_downlink(topic, payload)
    -- log.info("下行topic", topic)
    -- log.info("下行payload长度", #payload)
    -- log.info("下行payload", payload:sub(0, 64))
    if topic == service_invoke then
        -- log.info("收到RTK下发差分数据", payload)
        local jdata = json.decode(payload)
        if jdata then
            -- 示例数据
            --[[
                {   "id":"42",
                    "version":"1.0",
                    "params":{
                        "data":[
                            "0wCkQy2XQ7V/Aj+ACMCAIQAAAAAgIEEAf/5/IiIlJCam9PfJ35Wyw6iaMXri9AZW+/79Lfs39BgBwFSAroFffPL9WnT5B2oNBCM6hXaXbTwEdCQRa8BFrcEUWf9Ka/7Q//tDP/M+/8c7/p1P+nS/6H8ALSgCwyDK20MEZwwRoC/CrxLT+/qC7+oD/////////////8AAAXW454Z451323V0zST1WU0A1gIzTAQpGTZdDtKRAP4B3YJIGAAAAACCC",
                            "AAB////9tnx8eYJ3eXl6d1VRTUoOx2wFb1UeWGeI9UnoFRbIgAuCWQSf6z/kV8MQRiDhQboH6xYaLZOz13MO7P96fyb+u9svuUt3GFSw0WHNMvRnW9APqGtfDzMOsuBrAeT1wPCR/Jr/61ifsNz+SFv4udfNol/quH9xQ/jQ7/gdIFcA/mJX9DrXz7e/N43+6z33F/fW9T6soXq38epbUAKTv+XAf0lp45nnjVV+LX148p3iKE+09R65igC0eAMn",
                            "V+Dkf41Qf//////////////////////4AAAAALbb67cL8MZqKMMs78s78M7cMcsMqrLLsMsswE7+QQ=="],
                        "header":{"length":592,"tag":0}
                    }
                }
            ]]
            local data = jdata["params"]["data"]
            local tmp = table.concat(data, "")
            tmp = tmp:fromBase64()
            log.info("uart","写入差分数据", #tmp, "字节", "解码前的长度", jdata["params"]["header"]["length"])
            gnss_write(tmp)
        end
    end
end

sys.taskInit(function()
    -- 等待联网
    sys.waitUntil("net_ready")

    -- 打印一下上报(pub)和下发(sub)的topic名称
    -- 上报: 设备 ---> 服务器
    -- 下发: 设备 <--- 服务器
    -- 可使用mqtt.x等客户端进行调试
    log.info("mqtt", "pub", pub_topic)
    log.info("mqtt", "sub", sub_topic)
    log.info("mqtt", mqtt_host, mqtt_port, client_id, user_name, password)

    -------------------------------------
    -------- MQTT 演示代码 --------------
    -------------------------------------

    mqttc = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_isssl, ca_file)

    mqttc:auth(client_id, user_name, password) -- client_id必填,其余选填
    -- mqttc:keepalive(240) -- 默认值240s
    mqttc:autoreconn(true, 15000) -- 自动重连机制

    mqttc:on(function(mqtt_client, event, data, payload)
        -- 用户自定义代码
        -- log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then
            -- 联上了
            sys.publish("mqtt_conack")
            local topics = {}
            -- 物模型的topic
            topics[sub_topic] = 1

            -- 透传模式的topic
            -- 首先是 上报后, 服务器会回复
            if pub_custome_reply then
                topics[pub_custome_reply] = 1
            end
            -- 然后是 服务器的下发
            if sub_custome then
                topics[sub_custome] = 1
            end
            -- GGA上行之后的回复
            if pub_event then
                topics[pub_event_reply] = 1
            end
            -- 服务执行
            if service_invoke then
                topics[service_invoke] = 1
            end
            -- mqtt_client:subscribe(sub_topic, 2)--单主题订阅
            mqtt_client:subscribe(topics) -- 多主题订阅
        elseif event == "recv" then
            -- 打印收到的内容, 时间生产环境建议注释掉, 不然挺多的
            -- log.info("mqtt", "downlink", "topic", data, "payload", payload)
            on_downlink(data, payload)
        elseif event == "sent" then
            -- log.info("mqtt", "sent", "pkgid", data)
        end
    end)

    -- mqttc自动处理重连, 除非自行关闭
    mqttc:connect()
    sys.waitUntil("mqtt_conack")
    while true do
        sys.wait(60000)
    end
    mqttc:close()
    mqttc = nil
end)


return demo
