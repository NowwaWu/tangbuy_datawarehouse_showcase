# -*- coding: utf-8 -*-
"""
使用 qqwry 离线数据库解析缺失 IP 的地理位置。
纯真数据库处理速度快（秒级完成67k），不受 API 限速影响。
"""
import json
import time

INPUT_FILE = '/tmp/missing_ips.txt'
OUTPUT_FILE = '/tmp/ip_geo_result.csv'
FAIL_FILE = '/tmp/ip_failures.txt'

# ---------- 1. 加载 qqwry ----------
from qqwry import QQwry
q = QQwry()
q.load_file('/tmp/qqwry.dat')
print("qqwry database loaded.")

# ---------- 2. 读取 IP ----------
with open(INPUT_FILE, 'r') as f:
    ips = [line.strip() for line in f if line.strip()]
print(f"Total IPs to resolve: {len(ips)}")

# ---------- 3. 中文国名 → ISO 代码映射 ----------
CN_NAME_TO_ISO = {
    '中国': 'CN', '香港': 'HK', '澳门': 'MO', '台湾': 'TW',
    '美国': 'US', '日本': 'JP', '韩国': 'KR', '英国': 'GB',
    '德国': 'DE', '法国': 'FR', '加拿大': 'CA', '澳大利亚': 'AU',
    '新加坡': 'SG', '马来西亚': 'MY', '泰国': 'TH', '越南': 'VN',
    '印度': 'IN', '印度尼西亚': 'ID', '菲律宾': 'PH',
    '俄罗斯': 'RU', '巴西': 'BR', '意大利': 'IT', '西班牙': 'ES',
    '荷兰': 'NL', '瑞典': 'SE', '瑞士': 'CH', '新西兰': 'NZ',
    '阿联酋': 'AE', '沙特阿拉伯': 'SA', '南非': 'ZA',
    '墨西哥': 'MX', '阿根廷': 'AR', '智利': 'CL',
    '土耳其': 'TR', '伊朗': 'IR', '巴基斯坦': 'PK',
    '孟加拉': 'BD', '尼日利亚': 'NG', '埃及': 'EG',
    '乌克兰': 'UA', '波兰': 'PL', '比利时': 'BE', '奥地利': 'AT',
    '挪威': 'NO', '丹麦': 'DK', '芬兰': 'FI', '爱尔兰': 'IE',
    '葡萄牙': 'PT', '捷克': 'CZ', '罗马尼亚': 'RO', '匈牙利': 'HU',
    '以色列': 'IL', '哥伦比亚': 'CO', '秘鲁': 'PE',
    '缅甸': 'MM', '柬埔寨': 'KH', '老挝': 'LA', '尼泊尔': 'NP',
    '蒙古': 'MN', '哈萨克斯坦': 'KZ', '乌兹别克斯坦': 'UZ',
    '科威特': 'KW', '卡塔尔': 'QA', '巴林': 'BH', '阿曼': 'OM',
    '伊拉克': 'IQ', '阿富汗': 'AF', '也门': 'YE', '约旦': 'JO',
    '黎巴嫩': 'LB', '塞浦路斯': 'CY', '希腊': 'GR',
    '保加利亚': 'BG', '克罗地亚': 'HR', '塞尔维亚': 'RS',
    '斯洛伐克': 'SK', '斯洛文尼亚': 'SI', '爱沙尼亚': 'EE',
    '拉脱维亚': 'LV', '立陶宛': 'LT', '白俄罗斯': 'BY',
    '摩尔多瓦': 'MD', '格鲁吉亚': 'GE', '亚美尼亚': 'AM',
    '阿塞拜疆': 'AZ', '摩洛哥': 'MA', '突尼斯': 'TN', '阿尔及利亚': 'DZ',
    '利比亚': 'LY', '苏丹': 'SD', '肯尼亚': 'KE', '坦桑尼亚': 'TZ',
    '乌干达': 'UG', '埃塞俄比亚': 'ET', '加纳': 'GH', '科特迪瓦': 'CI',
    '塞内加尔': 'SN', '安哥拉': 'AO', '莫桑比克': 'MZ',
    '委内瑞拉': 'VE', '厄瓜多尔': 'EC', '玻利维亚': 'BO',
    '巴拉圭': 'PY', '乌拉圭': 'UY', '古巴': 'CU', '巴拿马': 'PA',
    '哥斯达黎加': 'CR', '危地马拉': 'GT', '洪都拉斯': 'HN',
    '萨尔瓦多': 'SV', '尼加拉瓜': 'NI', '牙买加': 'JM',
    '多米尼加': 'DO', '海地': 'HT', '波多黎各': 'PR',
    '特立尼达和多巴哥': 'TT', '斐济': 'FJ', '巴布亚新几内亚': 'PG',
    '马尔代夫': 'MV', '斯里兰卡': 'LK',
    'IANA': '未知', '未知': '未知', '保留地址': '未知',
    '欧洲': '未知', '非洲地区': '未知', '非洲': '未知', '亚洲': '未知',
    '亚太地区': '未知', '北美': '未知', '南美': '未知', '大洋洲': '未知',
    '毛里求斯': 'MU', '冰岛': 'IS', '卢森堡': 'LU', '马耳他': 'MT',
    '列支敦士登': 'LI', '摩纳哥': 'MC', '安道尔': 'AD',
    '圣马力诺': 'SM', '梵蒂冈': 'VA', '巴勒斯坦': 'PS',
    '叙利亚': 'SY', '吉尔吉斯斯坦': 'KG', '塔吉克斯坦': 'TJ',
    '土库曼斯坦': 'TM', '文莱': 'BN', '东帝汶': 'TL',
    '津巴布韦': 'ZW', '赞比亚': 'ZM', '马达加斯加': 'MG',
    '喀麦隆': 'CM', '刚果': 'CG', '刚果民主共和国': 'CD',
    '加蓬': 'GA', '赤道几内亚': 'GQ', '纳米比亚': 'NA',
    '博茨瓦纳': 'BW', '卢旺达': 'RW', '布隆迪': 'BI',
    '索马里': 'SO', '吉布提': 'DJ', '厄立特里亚': 'ER',
    '南苏丹': 'SS', '中非': 'CF', '乍得': 'TD', '尼日尔': 'NE',
    '布基纳法索': 'BF', '马里': 'ML', '毛里塔尼亚': 'MR',
    '几内亚': 'GN', '几内亚比绍': 'GW', '塞拉利昂': 'SL',
    '利比里亚': 'LR', '多哥': 'TG', '贝宁': 'BJ',
    '冈比亚': 'GM', '斯威士兰': 'SZ', '莱索托': 'LS',
    '科摩罗': 'KM', '塞舌尔': 'SC', '佛得角': 'CV',
    '圣多美和普林西比': 'ST', '马拉维': 'MW',
    '苏里南': 'SR', '圭亚那': 'GY', '巴巴多斯': 'BB',
    '巴哈马': 'BS', '伯利兹': 'BZ', '格林纳达': 'GD',
    '圣卢西亚': 'LC', '圣基茨和尼维斯': 'KN',
    '安提瓜和巴布达': 'AG', '多米尼克': 'DM',
    '圣文森特和格林纳丁斯': 'VC',
    '斐济群岛': 'FJ', '所罗门群岛': 'SB', '瓦努阿图': 'VU',
    '萨摩亚': 'WS', '汤加': 'TO', '基里巴斯': 'KI',
    '密克罗尼西亚': 'FM', '马绍尔群岛': 'MH', '帕劳': 'PW',
    '瑙鲁': 'NR', '图瓦卢': 'TV', '库克群岛': 'CK',
    '不丹': 'BT', '马尔代夫群岛': 'MV',
    # 纯真数据库中的别名
    '巴勒斯坦国': 'PS', '象牙海岸': 'CI', '北马其顿': 'MK',
    '黑山': 'ME', '波斯尼亚和黑塞哥维那': 'BA', '波黑': 'BA',
    '阿尔及利亚': 'DZ',  # explicit alias ensure match
}

# 中国省份简称映射
CN_PROVINCE_MAP = {
    '北京': '北京', '北京市': '北京',
    '上海': '上海', '上海市': '上海',
    '天津': '天津', '天津市': '天津',
    '重庆': '重庆', '重庆市': '重庆',
    '广东': '广东', '广东省': '广东',
    '浙江': '浙江', '浙江省': '浙江',
    '江苏': '江苏', '江苏省': '江苏',
    '山东': '山东', '山东省': '山东',
    '河南': '河南', '河南省': '河南',
    '河北': '河北', '河北省': '河北',
    '四川': '四川', '四川省': '四川',
    '湖北': '湖北', '湖北省': '湖北',
    '湖南': '湖南', '湖南省': '湖南',
    '福建': '福建', '福建省': '福建',
    '安徽': '安徽', '安徽省': '安徽',
    '江西': '江西', '江西省': '江西',
    '辽宁': '辽宁', '辽宁省': '辽宁',
    '吉林': '吉林', '吉林省': '吉林',
    '黑龙江': '黑龙江', '黑龙江省': '黑龙江',
    '山西': '山西', '山西省': '山西',
    '陕西': '陕西', '陕西省': '陕西',
    '广西': '广西', '广西壮族自治区': '广西', '广西区': '广西',
    '云南': '云南', '云南省': '云南',
    '贵州': '贵州', '贵州省': '贵州',
    '甘肃': '甘肃', '甘肃省': '甘肃',
    '内蒙古': '内蒙古', '内蒙古自治区': '内蒙古',
    '新疆': '新疆', '新疆维吾尔自治区': '新疆',
    '西藏': '西藏', '西藏自治区': '西藏',
    '宁夏': '宁夏', '宁夏回族自治区': '宁夏',
    '青海': '青海', '青海省': '青海',
    '海南': '海南', '海南省': '海南',
}


def parse_qqwry_result(ip, result):
    """
    解析 qqwry 返回结果，输出 (ip, cntry_cd, prov, city)
    qqwry 返回格式: (location, isp_detail) 
    例如:
      - 中国IP: ('江苏省南京市', '电信DNS服务器')
      - 外国IP: ('澳大利亚', '墨尔本Telstra')
      - 保留IP: ('IANA', '保留地址')
    """
    if not result or result[0] is None:
        return (ip, '未知', '未知', '未知')
    
    location = result[0].strip()
    isp_detail = result[1].strip() if len(result) > 1 else ''
    
    # 处理 IANA/保留地址
    if location in ('IANA', '保留地址', '', '本机地址'):
        return (ip, '未知', '未知', '未知')
    
    # 检查是否为中国 IP (包含中国省份信息)
    # 先尝试从 location 中匹配省份
    matched_prov = None
    for key, prov_name in sorted(CN_PROVINCE_MAP.items(), key=lambda x: -len(x[0])):
        if location.startswith(key) or key in location:
            matched_prov = prov_name
            break
    
    if matched_prov:
        # 中国 IP
        cntry_cd = 'CN'
        prov = matched_prov
        
        # 提取城市: 从 location 中移除省份部分，剩余部分作为城市
        # 找到匹配的 key 在 location 中的位置
        city = location
        for key in sorted(CN_PROVINCE_MAP.keys(), key=lambda x: -len(x)):
            if key in city:
                city = city.replace(key, '')
                break
        city = city.strip()
        
        # 如果城市包含 ISP 名称(常见: "市"字后面可能无内容)，清理
        if not city:
            city = '未知'
        
        # 如果 isp_detail 看起来像城市名(不含"公司""网络""电信"等), 且 city 为空，使用 isp_detail
        isp_keywords = ('公司', '网络', '电信', '联通', '移动', '网通', '铁通', 'DNS', '服务器', '信息', '科技', '互联')
        if city == '未知' and isp_detail and not any(k in isp_detail for k in isp_keywords):
            city = isp_detail
        
        return (ip, cntry_cd, prov, city)
    
    # 尝试匹配中文国名
    cntry_cd = '未知'
    matched_country = None
    for cn_name, iso in sorted(CN_NAME_TO_ISO.items(), key=lambda x: -len(x[0])):
        if location.startswith(cn_name) or cn_name in location:
            cntry_cd = iso
            matched_country = cn_name
            break
    
    if cntry_cd == 'CN':
        # 中国 IP 但无省份信息 (如 location='中国')
        return (ip, 'CN', '未知', '未知')
    
    if cntry_cd != '未知':
        # 外国 IP: 从 location 中移除国名，剩余作为地区/城市
        region_city = location
        if matched_country:
            region_city = region_city.replace(matched_country, '').strip()
        
        prov = region_city if region_city else '未知'
        city = '未知'
        
        # 尝试从 isp_detail 中提取城市信息 (过滤 ISP 名称)
        isp_blacklist = ('CZ88.NET', 'CZ88', '公司', '网络', '电信', '联通', '移动', '网通', '铁通',
                         'DNS', '服务器', '信息', '科技', '互联', '通讯', 'Telstra', 'ISP',
                         'Hosting', 'Cloud', 'Internet', 'Broadband', 'Mobile', 'Wireless',
                         'Cable', 'Fiber', 'Technology', 'Limited', 'LLC', 'Inc', 'Corp',
                         'Telecom', 'Networks', 'Services', 'Solutions', 'Communications',
                         'Broadband', 'Data', 'Access', 'Telecomunicaciones', 'Telecomunicacoes',
                         'SRL', 'SAS', 'SASU', 'SARL', 'GmbH', 'AG', 'BV', 'NV', 'AB', 'AS',
                         'SA de CV', 'SA de', 'SPA', 'SRLS', 'EURL', 'Ltd.', 'PLC', 'PTE', 'PTY')
        isp_detail_clean = isp_detail.strip()
        if isp_detail_clean and not any(k in isp_detail_clean for k in isp_blacklist):
            city = isp_detail_clean
        
        if city == '未知' and region_city:
            city = region_city
        
        return (ip, cntry_cd, prov, city)
    
    # 无法识别的情况
    return (ip, '未知', '未知', '未知')


# ---------- 4. 批量解析 ----------
results = []
failures = []
total = len(ips)
start_time = time.time()

for i, ip in enumerate(ips):
    try:
        result = q.lookup(ip)
        parsed = parse_qqwry_result(ip, result)
        results.append(parsed)
    except Exception as e:
        results.append((ip, '未知', '未知', '未知'))
        failures.append(ip)
    
    if (i + 1) % 5000 == 0:
        elapsed = time.time() - start_time
        speed = (i + 1) / elapsed
        print(f"  [{i+1:6d}/{total}] {(i+1)/total*100:5.1f}% | speed: {speed:.0f} IP/s", flush=True)

elapsed = time.time() - start_time
print(f"\nDone! {len(ips)} IPs resolved in {elapsed:.1f}s ({len(ips)/elapsed:.0f} IP/s)")
print(f"Failures: {len(failures)}")

# ---------- 5. 输出 CSV ----------
print(f"\nWriting to {OUTPUT_FILE}...")
with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
    f.write('register_ip,cntry_cd,prov,city\n')
    for ip, cntry, prov, city in results:
        esc_ip = ip.replace('"', '""')
        esc_cntry = cntry.replace('"', '""')
        esc_prov = prov.replace('"', '""')
        esc_city = city.replace('"', '""')
        f.write(f'"{esc_ip}","{esc_cntry}","{esc_prov}","{esc_city}"\n')
print(f"Saved {len(results)} rows to {OUTPUT_FILE}")

# ---------- 6. 统计概览 ----------
from collections import Counter
cntry_stats = Counter(r[1] for r in results)
print(f"\nCountry distribution (top 15):")
for cntry, cnt in cntry_stats.most_common(15):
    print(f"  {cntry}: {cnt}")

if failures:
    with open(FAIL_FILE, 'w') as f:
        for ip in failures:
            f.write(ip + '\n')
    print(f"\nFailed IPs saved to {FAIL_FILE}")
