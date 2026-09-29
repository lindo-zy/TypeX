// 日期时间：弹出 4 种格式候选菜单，点选后按当前输出模式写入（建议配「插入」模式）
async function main() {
    const d = new Date();
    const p = n => String(n).padStart(2, '0');
    const dateCN = d.getFullYear() + '年' + p(d.getMonth() + 1) + '月' + p(d.getDate()) + '日';
    const dateISO = d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate());
    const time = p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
    return [dateCN, dateISO, dateCN + time, dateISO + ' ' + time];
}
