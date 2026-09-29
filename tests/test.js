async function main(str) {

    str = encodeURIComponent(str);
    return [
        {
            type: 'urlInApp',
            title: '拼多多搜索',
            content: 'pinduoduo://com.xunmeng.pinduoduo/search_result.html?search_key=' + str
        },
        {
            type: 'urlInApp',
            title: '淘宝搜索',
            content: 'taobao://s.taobao.com/?q=' + str
        },
        {
            type: 'urlInApp',
            title: '京东搜索',
            content: `openjd://virtual?params=%7B%22des%22:%22productList%22,%22keyWord%22:%22${str}%22,%22from%22:%22search%22,%22category%22:%22jump%22%7D`
        },
        {
            type: 'urlInApp',
            title: '小红书搜索',
            content: `xhsdiscover://search/result?keyword=${str}`
        },
        {
            type: 'urlInApp',
            title: '高德地图搜索',
            content: `iosamap://path?sourceApplication=launch&backScheme=launch:&dname=${str}&dev=0&m=0&t=0`
        },
        {
            type: 'urlInApp',
            title: '哔哩哔哩搜索',
            content: `bilibili://search?keyword=${str}`
        },
        {
            type: 'urlInApp',
            title: '谷歌搜索',
            content: 'Alook://https://www.google.com/search?q=' + str
        },
        {
            type: 'urlInApp',
            title: 'Alook搜索',
            content: `Alook://${str}`
        },
        {
            type: 'urlInApp',
            title: 'piico最近照片',
            content: 'piiico://last-photo'
        },
        {
            type: 'urlInApp',
            title: '闲鱼',
            content: 'fleamarket://'
        },
        {
            type: 'function',
            title: '今日油价',
            content: 'youjia'
        },
        {
            type: 'function',
            title: '天气',
            content: 'tianqi',
            args: [str]
        },
        {
            type: 'function',
            title: '日期时间',
            content: 'riqi'
        }
    ];

}

async function youjia() {

    const baseURL = "http://api.yujn.cn/api/youjia.php?msg=四川";
    const result = await $http.get({ url: encodeURI(baseURL) });
    const data = JSON.parse(result);
    // 解析返回的JSON数据
    const city = data.city;
    const tips = data.tips;
    const prices = data.prices;

    let readableString = `城市：${city}\n`;
    readableString += `油价调整提示：${tips}\n`;
    readableString += `油价信息：\n`;

    // 遍历油价数据并生成字符串
    prices.forEach(priceInfo => {
        readableString += `${priceInfo.title}：${priceInfo.price}元/升\n`;
    });
    return readableString.replaceAll('#', '-');
}

async function tianqi(str = '') {
    const [lat, lon] = (str.trim() || '31.23,121.47').split(',').map(s => s.trim());
    const url = 'https://api.open-meteo.com/v1/forecast?latitude=' + encodeURIComponent(lat) +
                '&longitude=' + encodeURIComponent(lon) + '&current=temperature_2m,wind_speed_10m';
    const now = JSON.parse(await $http.get({ url })).current;
    return `当前气温 ${now.temperature_2m}°C，风速 ${now.wind_speed_10m} km/h`;
}

async function riqi() {
    const d = new Date();
    const p = n => String(n).padStart(2, '0');
    const dateCN = d.getFullYear() + '年' + p(d.getMonth() + 1) + '月' + p(d.getDate()) + '日';
    const dateISO = d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate());
    const time = p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
    return [dateCN, dateISO, dateCN + time, dateISO + ' ' + time];
}