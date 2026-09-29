async function main(str) {
    return [{ type: 'function', title: '查天气', content: 'tianqi', args: [str] }];
}

async function tianqi(str = '') {
    str = String(str).trim();
    if (!str) return tianqiByCoords(30.66667, 104.06667, '成都');
    if (/^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$/.test(str)) {
        const [lat, lon] = str.split(',').map(s => s.trim());
        return tianqiByCoords(lat, lon, '坐标 ' + str);
    }
    const geo = JSON.parse(await $http.get({
        url: 'https://geocoding-api.open-meteo.com/v1/search?name=' + encodeURIComponent(str) +
             '&count=5&language=zh&format=json'
    }));
    if (!geo.results || !geo.results.length) return '找不到城市：' + str;
    if (geo.results.length === 1) {
        const c = geo.results[0];
        return tianqiByCoords(c.latitude, c.longitude, c.name);
    }
    return geo.results.map(c => ({
        type: 'function',
        title: `${c.name}（${[c.admin1, c.country].filter(Boolean).join('·')}）`,
        content: 'tianqiByCoords',
        args: [c.latitude, c.longitude, c.name]
    }));
}

async function tianqiByCoords(lat, lon, name = '') {
    const url = 'https://api.open-meteo.com/v1/forecast?latitude=' + encodeURIComponent(lat) +
                '&longitude=' + encodeURIComponent(lon) + '&current=temperature_2m,wind_speed_10m';
    const now = JSON.parse(await $http.get({ url })).current;
    return (name ? name + '：' : '') + `当前气温 ${now.temperature_2m}°C，风速 ${now.wind_speed_10m} km/h`;
}
