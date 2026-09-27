const resName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'esx_gangs';

let gangs = {};
let selected = null;
let maxRanks = 10;

const $ = (id) => document.getElementById(id);

function post(name, data) {
    fetch(`https://${resName}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data || {})
    });
}

function fmt(c) {
    if (!c || ![c.x, c.y, c.z].every(v => typeof v === 'number' && Number.isFinite(v))) return 'Not set';
    return `${c.x.toFixed(1)}, ${c.y.toFixed(1)}, ${c.z.toFixed(1)}`;
}

function formatTime(raw) {
    if (raw == null || raw === '') return '-';
    let d;
    if (typeof raw === 'number') {
        d = new Date(raw > 1e12 ? raw : raw * 1000);
    } else if (/^\d+$/.test(String(raw))) {
        const n = Number(raw);
        d = new Date(n > 1e12 ? n : n * 1000);
    } else {
        d = new Date(String(raw).replace(' ', 'T'));
    }
    if (isNaN(d.getTime())) return String(raw);
    const p = (n) => String(n).padStart(2, '0');
    return `${p(d.getHours())}:${p(d.getMinutes())}`;
}
function formatDate(raw) {
    if (raw == null || raw === '') return '';
    let d;
    if (typeof raw === 'number') {
        d = new Date(raw > 1e12 ? raw : raw * 1000);
    } else if (/^\d+$/.test(String(raw))) {
        const n = Number(raw);
        d = new Date(n > 1e12 ? n : n * 1000);
    } else {
        d = new Date(String(raw).replace(' ', 'T'));
    }
    if (isNaN(d.getTime())) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return `${d.getDate()} ${months[d.getMonth()]}`;
}

function renderList() {
    const box = $('gangList');
    box.innerHTML = '';
    Object.values(gangs).forEach((g) => {
        const el = document.createElement('div');
        const on = g.active !== false;
        el.className = 'gang-item' + (selected === g.name ? ' active' : '') + (on ? '' : ' off');
        const dot = document.createElement('span');
        dot.className = 'dot' + (on ? '' : ' off');
        el.appendChild(dot);
        el.appendChild(document.createTextNode(g.label + '  (' + g.name + ')'));
        el.onclick = () => {
            selected = g.name;
            render();
        };
        box.appendChild(el);
    });
}

function expiryText(g) {
    if (!g.expiresAt || !Number.isFinite(g.expiresAt)) return 'Period: unlimited — never expires';
    const now = Math.floor(Date.now() / 1000);
    const left = g.expiresAt - now;
    const days = Math.ceil(left / 86400);
    const d = new Date(g.expiresAt * 1000);
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const when = `${d.getDate()} ${months[d.getMonth()]} ${d.getFullYear()}`;
    const period = (g.renewDays != null ? g.renewDays : 30) + '-day period';
    if (left <= 0) return `${period} · Expired ${when} — auto-disabled`;
    return `${period} · Expires ${when} (${days} day${days === 1 ? '' : 's'} left)`;
}

function refreshEditorStatus() {
    if ($('app').classList.contains('hidden')) return;
    renderList();
    if (!selected || !gangs[selected]) return;
    const g = gangs[selected];
    const on = g.active !== false;
    const st = $('edStatus');
    if (st) {
        st.textContent = on ? 'Active' : 'Disabled';
        st.className = 'status ' + (on ? 'on' : 'off');
    }
    const ex = $('edExpiry');
    if (ex) ex.textContent = expiryText(g);
}

function renderRanks(g) {
    const box = $('rankList');
    box.innerHTML = '';
    (g.ranks || []).forEach((r, i) => {
        const row = document.createElement('div');
        row.className = 'rank';
        row.innerHTML = `
            <input type="number" min="0" value="${r.grade}" data-i="${i}" class="rg" />
            <input type="text" value="${r.label}" data-i="${i}" class="rl" maxlength="40" />
            <button data-del="${i}">×</button>
        `;
        box.appendChild(row);
    });
    box.querySelectorAll('[data-del]').forEach((b) => {
        b.onclick = () => {
            g.ranks.splice(Number(b.dataset.del), 1);
            renderRanks(g);
        };
    });
}

function collectRanks() {
    const grades = [...document.querySelectorAll('.rg')];
    const labels = [...document.querySelectorAll('.rl')];
    return grades.map((el, i) => ({
        grade: Number(el.value),
        label: labels[i].value
    }));
}

function renderVeh(g) {
    const ul = $('vehList');
    ul.innerHTML = '';
    if (!g.vehicles || !g.vehicles.length) {
        ul.innerHTML = '<li>No vehicles</li>';
        return;
    }
    g.vehicles.forEach((v) => {
        const li = document.createElement('li');
        li.innerHTML = `<span>${v.label} <b>${v.model}</b></span>`;
        const btn = document.createElement('button');
        btn.textContent = 'Remove';
        btn.onclick = () => post('removeVehicle', { gang: g.name, model: v.model });
        li.appendChild(btn);
        ul.appendChild(li);
    });
}

function render() {
    renderList();
    if (!selected || !gangs[selected]) {
        $('empty').classList.remove('hidden');
        $('editor').classList.add('hidden');
        return;
    }
    const g = gangs[selected];
    $('empty').classList.add('hidden');
    $('editor').classList.remove('hidden');
    $('edTitle').textContent = g.label;
    $('edName').textContent = g.name;
    const on = g.active !== false;
    $('edStatus').textContent = on ? 'Active' : 'Disabled';
    $('edStatus').className = 'status ' + (on ? 'on' : 'off');
    $('edExpiry').textContent = expiryText(g);
    const daysInput = $('renewDays');
    if (daysInput && document.activeElement !== daysInput) {
        daysInput.value = g.renewDays != null ? g.renewDays : 30;
    }
    $('metaParking').textContent = 'Parking: ' + fmt(g.parking) + ' | Spawn: ' + fmt(g.spawn);
    $('metaStash').textContent = fmt(g.stash);
    $('metaWardrobe').textContent = fmt(g.wardrobe);
    $('metaBoss').textContent = fmt(g.boss);
    $('metaCraft').textContent = fmt(g.craft);
    renderRanks(g);
    renderVeh(g);
    renderRecipes(g);
}

function renderRecipes(g) {
    const box = $('recipeList');
    if (!box) return;
    box.innerHTML = '';
    const list = g.recipes || [];
    list.forEach((rec, i) => {
        box.appendChild(recipeEl(rec, i));
    });
}

function recipeEl(rec, i) {
    const wrap = document.createElement('div');
    wrap.className = 'recipe';
    wrap.innerHTML = `
        <div class="row">
            <input class="r-label" placeholder="Label" value="${rec.label || ''}" />
            <input class="r-result" placeholder="Result item (spawn name)" value="${rec.result || ''}" />
            <input class="r-count" type="number" min="1" placeholder="Count" value="${rec.resultCount || 1}" style="max-width:90px" />
            <input class="r-time" type="number" min="1" placeholder="Time sec" value="${rec.time || 5}" style="max-width:100px" />
            <button class="danger r-del">×</button>
        </div>
        <div class="ings"></div>
        <button class="ghost r-add">+ Ingredient</button>
    `;
    const ings = wrap.querySelector('.ings');
    const addIng = (ing) => {
        const row = document.createElement('div');
        row.className = 'ing';
        row.innerHTML = `<input class="i-item" placeholder="Needed item" value="${ing.item || ''}" />
            <input class="i-count" type="number" min="1" value="${ing.count || 1}" />
            <button class="danger i-del">×</button>`;
        row.querySelector('.i-del').onclick = () => row.remove();
        ings.appendChild(row);
    };
    (rec.ingredients && rec.ingredients.length ? rec.ingredients : [{ item: '', count: 1 }]).forEach(addIng);
    wrap.querySelector('.r-add').onclick = () => addIng({ item: '', count: 1 });
    wrap.querySelector('.r-del').onclick = () => wrap.remove();
    return wrap;
}

function collectRecipes() {
    return [...document.querySelectorAll('.recipe')].map((el) => ({
        label: el.querySelector('.r-label').value,
        result: el.querySelector('.r-result').value,
        resultCount: Number(el.querySelector('.r-count').value),
        time: Number(el.querySelector('.r-time').value),
        ingredients: [...el.querySelectorAll('.ing')].map((row) => ({
            item: row.querySelector('.i-item').value,
            count: Number(row.querySelector('.i-count').value)
        }))
    }));
}

let bossData = null;
let selectedNegotiationGang = null;
let selectedGroupId = null;
let selectedChatType = 'direct'; // direct or group
let currentChats = [];
let lastChatTarget = null;
let clientGangs = {};
let allGroups = [];
let blockedMap = {};
let blockedByMap = {};

function hideAll() {
    $('app').classList.add('hidden');
    $('boss').classList.add('hidden');
}

function badgeForStatus(st) {
    const s = (st || 'neutral').toLowerCase();
    if (s === 'ally' || s === 'friend') return `<span class="badge ally">Ally</span>`;
    if (s === 'enemy') return `<span class="badge enemy">Enemy</span>`;
    return `<span class="badge neutral">Neutral</span>`;
}

function getAllGangsForUI() {
    let src = null;
    if (bossData && bossData.allGangs && Object.keys(bossData.allGangs).length > 0) {
        src = bossData.allGangs;
    } else if (clientGangs && Object.keys(clientGangs).length > 0) {
        src = clientGangs;
    } else if (gangs && Object.keys(gangs).length > 0) {
        src = gangs;
    } else {
        src = {};
    }
    return src;
}

function getAvatarLetter(name) {
    if (!name) return '?';
    return name.trim().charAt(0).toUpperCase();
}

function renderSides() {
    const box = $('sidesList');
    if (!box) return;
    box.innerHTML = '';
    if (!bossData) return;
    const allGangsObj = getAllGangsForUI();
    const allGangs = Object.values(allGangsObj);
    const myGangName = bossData.gang?.name;
    const myRels = bossData.myRelations || {};
    const theirRels = bossData.theirRelations || {};

    const filtered = allGangs.filter(g => g.name !== myGangName);
    if (!filtered.length) {
        const total = allGangs.length;
        if (total === 0) {
            box.innerHTML = '<div class="mrow"><div class="info">No gangs found in DB</div></div>';
        } else if (total === 1 && myGangName) {
            box.innerHTML = '<div class="mrow"><div class="info">Only your gang exists ('+myGangName+')</div></div>';
        } else {
            box.innerHTML = '<div class="mrow"><div class="info">No other gangs found</div></div>';
        }
        return;
    }
    filtered.forEach((g) => {
        const myStatus = myRels[g.name] || 'neutral';
        const theirStatus = theirRels[g.name] || 'neutral';
        const row = document.createElement('div');
        row.className = 'mrow';
        const info = document.createElement('div');
        info.className = 'info';
        info.innerHTML = `<b>${g.label}</b><small>${g.name}</small>`;
        const myCol = document.createElement('div');
        myCol.innerHTML = badgeForStatus(myStatus);
        const theirCol = document.createElement('div');
        theirCol.innerHTML = badgeForStatus(theirStatus);

        const actions = document.createElement('div');
        actions.className = 'side-actions';
        const makeBtn = (label, status) => {
            const b = document.createElement('button');
            b.textContent = label;
            if ((myStatus || 'neutral').toLowerCase() === status || (status === 'ally' && (myStatus === 'friend' || myStatus === 'ally'))) {
                b.classList.add('on');
            }
            if (status === 'ally') b.className += ' up';
            if (status === 'enemy') b.className += ' danger';
            if (status === 'neutral') b.className += ' ghost';
            b.onclick = () => {
                post('setRelation', { target: g.name, status: status });
            };
            return b;
        };
        actions.appendChild(makeBtn('Ally', 'ally'));
        actions.appendChild(makeBtn('Neutral', 'neutral'));
        actions.appendChild(makeBtn('Enemy', 'enemy'));

        row.appendChild(info);
        row.appendChild(myCol);
        row.appendChild(theirCol);
        row.appendChild(actions);
        box.appendChild(row);
    });
}

function renderGroups() {
    const box = $('groupList');
    if (!box) return;
    box.innerHTML = '';
    const groups = allGroups || bossData?.groups || [];
    if (!groups.length) {
        box.innerHTML = '<div style="padding:10px;text-align:center;color:#7d8b99;font-size:12px;">No groups yet<br><small>Create with + New Group</small></div>';
        return;
    }
    const searchVal = ($('tgSearch')?.value || '').toLowerCase();
    let filtered = groups;
    if (searchVal) {
        filtered = groups.filter(g => (g.label && g.label.toLowerCase().includes(searchVal)) || (g.name && g.name.toLowerCase().includes(searchVal)));
    }
    if (!filtered.length) {
        box.innerHTML = '<div style="padding:10px;text-align:center;color:#7d8b99;font-size:12px;">No matching groups</div>';
        return;
    }
    filtered.forEach((g) => {
        const el = document.createElement('div');
        el.className = 'tg-chat-item group' + (selectedChatType === 'group' && selectedGroupId === g.id ? ' active' : '');
        const letter = getAvatarLetter(g.label);
        const colors = ['#6ab0e7','#f28a6a','#a8d08d','#f7c873','#b893e6','#7bc8c4','#f0a6b5'];
        let hash = 0;
        for (let i=0;i<g.name.length;i++) hash = g.name.charCodeAt(i) + ((hash<<5)-hash);
        const col = colors[Math.abs(hash)%colors.length];
        const memberCount = g.members ? g.members.length : 0;
        el.innerHTML = `
            <div class="tg-chat-avatar" style="background:${col}">${letter}</div>
            <div class="tg-item-main">
                <div class="tg-item-top">
                    <span class="tg-item-name">${escapeHtml(g.label)} <span class="tg-group-badge">${memberCount}</span></span>
                </div>
                <div class="tg-item-sub">${escapeHtml(g.members ? g.members.join(', ') : '')}</div>
            </div>
        `;
        el.onclick = () => {
            selectedChatType = 'group';
            selectedGroupId = g.id;
            selectedNegotiationGang = null;
            renderGroups();
            renderNegotiationGangs();
            const titleEl = $('chatHeaderTitle');
            const subEl = $('chatHeaderSub');
            const avEl = $('chatAvatar');
            if (titleEl) titleEl.textContent = g.label;
            if (subEl) subEl.textContent = g.members ? g.members.join(', ') : g.name;
            if (avEl) { avEl.textContent = letter; avEl.style.background = col; }
            $('chatList').innerHTML = '<div style="color:#7d8b99;text-align:center;padding:20px;">Loading group chat...</div>';
            post('getGroupChats', { groupId: g.id });
        };
        box.appendChild(el);
    });
}

function renderNegotiationGangs() {
    const box = $('negotiationGangList');
    if (!box) return;
    box.innerHTML = '';
    if (!bossData) return;
    const allGangsObj = getAllGangsForUI();
    const allGangs = Object.values(allGangsObj);
    const myGangName = bossData.gang?.name;
    let filtered = allGangs.filter(g => g.name !== myGangName);

    const searchVal = ($('tgSearch')?.value || '').toLowerCase();
    if (searchVal) {
        filtered = filtered.filter(g => g.label.toLowerCase().includes(searchVal) || g.name.toLowerCase().includes(searchVal));
    }

    if (!filtered.length) {
        const total = allGangs.length;
        if (total <= 1) {
            box.innerHTML = '<div style="padding:10px;text-align:center;color:#7d8b99;font-size:12px;">No other gangs</div>';
        } else {
            box.innerHTML = '<div style="padding:10px;text-align:center;color:#7d8b99;font-size:12px;">No matching gangs</div>';
        }
        return;
    }
    filtered.forEach((g) => {
        const el = document.createElement('div');
        const isBlocked = blockedMap && blockedMap[g.name];
        const isBlockedBy = blockedByMap && blockedByMap[g.name];
        let extraClass = '';
        if (isBlocked) extraClass = ' blocked';
        if (isBlockedBy) extraClass += ' blocked-by';
        el.className = 'tg-chat-item' + (selectedChatType === 'direct' && selectedNegotiationGang === g.name ? ' active' : '') + extraClass;
        const letter = getAvatarLetter(g.label);
        const colors = ['#6ab0e7','#f28a6a','#a8d08d','#f7c873','#b893e6','#7bc8c4','#f0a6b5'];
        let hash = 0;
        for (let i=0;i<g.name.length;i++) hash = g.name.charCodeAt(i) + ((hash<<5)-hash);
        const col = colors[Math.abs(hash)%colors.length];
        const blockBadge = isBlocked ? '<span style="background:#ff3b30;color:#fff;font-size:9px;padding:2px 5px;border-radius:8px;margin-left:6px;">BLOCKED</span>' : (isBlockedBy ? '<span style="background:#ff9500;color:#fff;font-size:9px;padding:2px 5px;border-radius:8px;margin-left:6px;">BLOCKED YOU</span>' : '');

        el.innerHTML = `
            <div class="tg-chat-avatar" style="background:${col}">${letter}</div>
            <div class="tg-item-main">
                <div class="tg-item-top">
                    <span class="tg-item-name">${escapeHtml(g.label)}${blockBadge}</span>
                </div>
                <div class="tg-item-sub">${escapeHtml(g.name)}</div>
            </div>
        `;
        el.onclick = () => {
            selectedChatType = 'direct';
            selectedNegotiationGang = g.name;
            selectedGroupId = null;
            renderNegotiationGangs();
            renderGroups();
            const titleEl = $('chatHeaderTitle');
            const subEl = $('chatHeaderSub');
            const avEl = $('chatAvatar');
            if (titleEl) titleEl.textContent = g.label;
            if (subEl) subEl.textContent = g.name;
            if (avEl) { avEl.textContent = letter; avEl.style.background = col; }
            $('chatList').innerHTML = '<div style="color:#7d8b99;text-align:center;padding:20px;">Loading...</div>';
            post('getChats', { target: g.name });
        };
        box.appendChild(el);
    });
}

function escapeHtml(str) {
    return String(str).replace(/[&<>"']/g, (m) => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[m]));
}

function parseExtra(c) {
    if (c.extraDecoded) return c.extraDecoded;
    if (c.extra) {
        try { return JSON.parse(c.extra); } catch(e){ return null; }
    }
    return null;
}

function renderChatList(chats, target) {
    const box = $('chatList');
    if (!box) return;
    box.innerHTML = '';
    lastChatTarget = target;
    currentChats = chats || [];
    if (!currentChats.length) {
        box.innerHTML = `
            <div style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;color:#7d8b99;padding:40px 20px;text-align:center;">
                <div style="width:80px;height:80px;background:#dbeaf0;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:36px;margin-bottom:16px;">💬</div>
                <b style="color:#2b5278;font-size:14px;">No messages yet</b>
                <span style="font-size:12.5px;margin-top:6px;max-width:240px;">Start conversation. Messages are saved.</span>
            </div>`;
        return;
    }
    const myGang = bossData?.gang?.name;
    let lastDate = '';
    currentChats.forEach((c) => {
        const dateStr = formatDate(c.ts || c.created_at);
        if (dateStr && dateStr !== lastDate) {
            const sep = document.createElement('div');
            sep.className = 'tg-date-sep';
            sep.textContent = dateStr;
            box.appendChild(sep);
            lastDate = dateStr;
        }
        const isMe = c.gang_from === myGang || c.sender_gang === myGang;
        const time = c.ts ? formatTime(c.ts) : (c.created_at ? formatTime(c.created_at) : '');
        const sender = c.sender_name || 'Unknown';
        const type = (c.type || 'text').toLowerCase();
        const extra = parseExtra(c);

        if (type === 'location' || type === 'love') {
            const el = document.createElement('div');
            el.className = 'chat-msg ' + (isMe ? 'me' : 'other');
            el.style.padding = '0';
            el.style.overflow = 'hidden';
            el.style.maxWidth = '68%';
            el.style.borderRadius = '12px';
            const x = extra?.x?.toFixed ? extra.x.toFixed(1) : (extra?.x || 0);
            const y = extra?.y?.toFixed ? extra.y.toFixed(1) : (extra?.y || 0);
            const kindLabel = type === 'love' ? '❤️ Love Location' : '📍 Location';
            el.innerHTML = `
                <div style="height:90px;background:linear-gradient(135deg,#a8d8f0 0%,#7ec8e6 50%,#a3d9a5 100%);display:flex;align-items:center;justify-content:center;font-size:32px;">${type==='love'?'❤️':'📍'}</div>
                <div style="padding:8px 10px;background:${isMe?'#eeffde':'#fff'};color:#000;">
                    <b style="font-size:11px;color:${isMe?'#5ca853':'#2AABEE'}">${escapeHtml(sender)}</b>
                    <p style="font-weight:600;margin:2px 0;">${kindLabel}</p>
                    <small style="color:#7d8b99;">X: ${x} Y: ${y}</small><br>
                    <small style="float:right;color:${isMe?'#5ca853':'#7d8b99'}">${time} ${isMe?'<span class="tg-check">✓✓</span>':''}</small>
                    <div style="clear:both"></div>
                </div>
            `;
            box.appendChild(el);
        } else {
            const el = document.createElement('div');
            el.className = 'chat-msg ' + (isMe ? 'me' : 'other');
            const check = isMe ? '<span class="tg-check">✓✓</span>' : '';
            const showSender = selectedChatType === 'group' && !isMe;
            el.innerHTML = `
                ${showSender ? `<b>${escapeHtml(sender)} <small style="opacity:0.6">(${escapeHtml(c.sender_gang||'')})</small></b>` : (!isMe ? `<b>${escapeHtml(sender)}</b>` : '')}
                <p>${escapeHtml(c.message || '')}</p>
                <small>${time} ${check}</small>
            `;
            box.appendChild(el);
        }
    });
    box.scrollTop = box.scrollHeight;
}

function renderGroupChats(chats, groupId) {
    // same as renderChatList but for groups, no target filter needed
    renderChatList(chats, 'group-'+groupId);
}

function renderGroupSelect() {
    const box = $('groupGangSelect');
    if (!box) return;
    box.innerHTML = '';
    const allGangsObj = getAllGangsForUI();
    const allGangs = Object.values(allGangsObj);
    const myGangName = bossData?.gang?.name;
    const filtered = allGangs.filter(g => g.name !== myGangName);
    if (!filtered.length) {
        box.innerHTML = '<div style="padding:10px;color:#7d8b99;">No other gangs to add</div>';
        return;
    }
    filtered.forEach((g) => {
        const label = document.createElement('label');
        label.innerHTML = `<input type="checkbox" value="${g.name}" /> <b>${escapeHtml(g.label)}</b> <small>(${escapeHtml(g.name)})</small>`;
        box.appendChild(label);
    });
}

function renderBoss() {
    if (!bossData) return;
    $('bossTitle').textContent = bossData.gang.label;
    $('bossMoney').textContent = '$' + (bossData.gang.money || 0).toLocaleString();
    const box = $('memberList');
    box.innerHTML = '';
    const members = bossData.members || [];
    if ($('memCount')) $('memCount').textContent = String(members.length);
    if (!members.length) {
        box.innerHTML = '<div class="mrow"><div class="info">No members yet. Use /setgang</div></div>';
    }
    members.forEach((m) => {
        const el = document.createElement('div');
        el.className = 'mrow';
        const info = document.createElement('div');
        info.className = 'info';
        const name = document.createElement('b');
        const dot = document.createElement('span');
        dot.className = 'dot ' + (m.online ? 'on' : 'off');
        name.appendChild(dot);
        name.appendChild(document.createTextNode(m.name || m.identifier));
        const small = document.createElement('small');
        small.textContent = m.online ? 'Online' : 'Offline';
        info.appendChild(name);
        info.appendChild(small);
        const rank = document.createElement('div');
        rank.className = 'rankcell';
        rank.textContent = m.rank || '-';
        const actions = document.createElement('div');
        actions.className = 'actions manage';
        const btn = document.createElement('button');
        btn.className = 'up';
        btn.textContent = 'Manage';
        const menu = document.createElement('div');
        menu.className = 'manage-menu';
        const mk = (cls, label, act) => {
            const b = document.createElement('button');
            b.className = cls;
            b.textContent = label;
            b.addEventListener('click', (e) => {
                e.stopPropagation();
                post('memberAction', { identifier: m.identifier, action: act });
            });
            return b;
        };
        menu.appendChild(mk('up', 'Rank up', 'promote'));
        menu.appendChild(mk('down', 'Rank down', 'demote'));
        menu.appendChild(mk('danger', 'Fire', 'fire'));
        btn.addEventListener('click', (e) => {
            e.stopPropagation();
            document.querySelectorAll('.manage.open').forEach((n) => { if (n !== actions) n.classList.remove('open'); });
            actions.classList.toggle('open');
        });
        actions.appendChild(btn);
        actions.appendChild(menu);
        el.appendChild(info);
        el.appendChild(rank);
        el.appendChild(actions);
        box.appendChild(el);
    });
    const cars = $('bossCars');
    cars.innerHTML = '';
    (bossData.gang.vehicles || []).forEach((v) => {
        const el = document.createElement('div');
        el.className = 'mrow';
        const st = v.impounded ? 'Impounded' : (v.stored ? 'Parked' : 'Out');
        const cls = v.stored ? 'online' : 'take';
        el.innerHTML = `<div class="info"><b>${v.label}</b><small>${v.model}</small></div><div class="actions"><span class="${cls}">${st}</span></div>`;
        cars.appendChild(el);
    });
    const cloth = $('clothRanks');
    cloth.innerHTML = '';
    const savedList = (bossData.gang.outfits && bossData.gang.outfits.savedGrades) || [];
    const saved = new Set(savedList.map((n) => Number(n)));
    (bossData.gang.ranks || []).forEach((r) => {
        const grade = Number(r.grade);
        const el = document.createElement('div');
        el.className = 'mrow';
        const ok = saved.has(grade);
        const name = document.createElement('div');
        name.className = 'info';
        name.innerHTML = `<b>${r.label}</b><small>rank ${grade}</small>
            <span class="${ok ? 'online' : 'offline'}">${ok ? 'Outfit saved' : 'Not set'}</span>`;
        const actions = document.createElement('div');
        actions.className = 'actions';
        const btn = document.createElement('button');
        btn.className = 'up';
        btn.textContent = 'Save outfit for this rank';
        btn.addEventListener('click', () => post('saveOutfit', { kind: 'rank', grade: grade }));
        actions.appendChild(btn);
        el.appendChild(name);
        el.appendChild(actions);
        cloth.appendChild(el);
    });
    const accBox = $('accessList');
    accBox.innerHTML = '';
    const g = bossData.gang;
    const acc = g.access || {};
    const feats = [
        { key: 'stash', title: 'Stash', ready: !!g.stash },
        { key: 'wardrobe', title: 'Wardrobe', ready: !!g.wardrobe },
        { key: 'parking', title: 'Parking', ready: !!g.parking },
        { key: 'craft', title: 'Craft table', ready: !!g.craft }
    ];
    feats.forEach((f) => {
        const el = document.createElement('div');
        el.className = 'mrow' + (f.ready ? '' : ' dim');
        const info = document.createElement('div');
        info.className = 'info';
        info.innerHTML = `<b>${f.title}</b><small>${f.ready ? 'Location set' : 'Not placed — set it in /creategang'}</small>`;
        const checks = document.createElement('div');
        checks.className = 'checks';
        const allowed = new Set((acc[f.key] || []).map(Number));
        (g.ranks || []).forEach((r) => {
            const lab = document.createElement('label');
            const cb = document.createElement('input');
            cb.type = 'checkbox';
            cb.checked = allowed.has(Number(r.grade));
            cb.addEventListener('change', () => {
                const grades = [];
                checks.querySelectorAll('input').forEach((inp) => {
                    if (inp.checked) grades.push(Number(inp.dataset.grade));
                });
                post('setAccess', { feature: f.key, grades });
            });
            cb.dataset.grade = String(r.grade);
            lab.appendChild(cb);
            lab.appendChild(document.createTextNode((r.label || 'Rank') + ' (' + r.grade + ')'));
            checks.appendChild(lab);
        });
        el.appendChild(info);
        el.appendChild(checks);
        accBox.appendChild(el);
    });
    const robOn = bossData.gang.outfits && bossData.gang.outfits.rob;
    $('robState').textContent = robOn ? 'Saved' : 'Not set';
    $('robState').className = robOn ? 'online' : 'offline';
    const logs = $('logList');
    logs.innerHTML = '';
    if (!bossData.logs || !bossData.logs.length) {
        logs.innerHTML = '<div class="mrow"><div class="info">No logs yet</div></div>';
    }
    (bossData.logs || []).forEach((l) => {
        const el = document.createElement('div');
        el.className = 'mrow';
        const act = l.action === 'put' ? 'Deposited' : 'Took';
        el.innerHTML = `<div class="info"><b class="${l.action}">${act}</b> item: ${l.item} — count: ${l.count}
            <small>player: ${l.player} · time: ${formatTime(l.created_at)}</small></div>`;
        logs.appendChild(el);
    });

    allGroups = bossData.groups || allGroups || [];
    blockedMap = bossData.blocked || blockedMap || {};
    blockedByMap = bossData.blockedBy || blockedByMap || {};
    renderSides();
    renderGroups();
    renderNegotiationGangs();
    if (selectedChatType === 'group' && selectedGroupId) {
        const gg = (allGroups || []).find(x => x.id === selectedGroupId);
        if (gg) {
            const titleEl = $('chatHeaderTitle');
            const subEl = $('chatHeaderSub');
            const avEl = $('chatAvatar');
            if (titleEl) titleEl.textContent = gg.label;
            if (subEl) subEl.textContent = gg.members ? gg.members.join(', ') : gg.name;
            if (avEl) avEl.textContent = getAvatarLetter(gg.label);
        }
    } else if (selectedNegotiationGang) {
        const allGangsObj = getAllGangsForUI();
        const gg = allGangsObj[selectedNegotiationGang];
        if (gg) {
            const titleEl = $('chatHeaderTitle');
            const subEl = $('chatHeaderSub');
            const avEl = $('chatAvatar');
            if (titleEl) titleEl.textContent = gg.label;
            if (subEl) subEl.textContent = gg.name;
            if (avEl) avEl.textContent = getAvatarLetter(gg.label);
        }
    }
}

window.addEventListener('message', (e) => {
    const d = e.data;
    if (!d || !d.action) return;
    if (d.action === 'open') {
        $('boss').classList.add('hidden');
        gangs = d.gangs || {};
        clientGangs = d.gangs || clientGangs;
        selected = d.selected || selected;
        maxRanks = d.maxRanks || 10;
        $('app').classList.remove('hidden');
        try { render(); } catch (err) { console.error('esx_gangs render:', err); }
    }
    if (d.action === 'openBoss') {
        $('app').classList.add('hidden');
        bossData = d.data;
        if (d.allGangs && Object.keys(d.allGangs).length > 0) {
            clientGangs = d.allGangs;
            if (!bossData.allGangs || Object.keys(bossData.allGangs).length === 0) {
                bossData.allGangs = d.allGangs;
            }
        }
        if (bossData.groups) allGroups = bossData.groups;
        if (bossData.blocked) blockedMap = bossData.blocked;
        if (bossData.blockedBy) blockedByMap = bossData.blockedBy;
        $('boss').classList.remove('hidden');
        renderBoss();
    }
    if (d.action === 'syncGangs') {
        clientGangs = d.gangs || {};
        gangs = d.gangs || gangs;
        if (bossData) {
            bossData.allGangs = d.gangs || bossData.allGangs;
            renderSides();
            renderNegotiationGangs();
            renderGroupSelect();
        }
        // رفرش نرم وضعیت (بدون دست زدن به اینپوت‌های در حال ادیت)
        refreshEditorStatus();
    }
    if (d.action === 'groups') {
        allGroups = d.groups || [];
        if (bossData) bossData.groups = allGroups;
        renderGroups();
        renderGroupSelect();
    }
    if (d.action === 'groupChats') {
        if (selectedChatType === 'group' && selectedGroupId === d.groupId) {
            renderGroupChats(d.chats || [], d.groupId);
        }
    }
    if (d.action === 'blocks') {
        const b = d.blocks || {};
        blockedMap = b.blocked || blockedMap;
        blockedByMap = b.blockedBy || blockedByMap;
        if (bossData) {
            bossData.blocked = blockedMap;
            bossData.blockedBy = blockedByMap;
        }
        renderNegotiationGangs();
    }
    if (d.action === 'close') {
        hideAll();
    }
    if (d.action === 'chats') {
        if (selectedChatType === 'direct' && d.target === selectedNegotiationGang) {
            renderChatList(d.chats || [], d.target);
        } else if (!selectedNegotiationGang && d.target && selectedChatType === 'direct') {
            selectedNegotiationGang = d.target;
            renderChatList(d.chats || [], d.target);
        }
    }
});

$('btnClose').onclick = () => {
    hideAll();
    post('close');
};

document.querySelectorAll('.tab').forEach((t) => {
    t.onclick = () => {
        document.querySelectorAll('.tab').forEach((x) => x.classList.remove('on'));
        t.classList.add('on');
        document.querySelectorAll('.tabpage').forEach((p) => p.classList.add('hidden'));
        $('tab-' + t.dataset.tab).classList.remove('hidden');
    };
});

$('bossClose').onclick = () => {
    hideAll();
    post('close');
};

$('btnDep').onclick = () => post('money', { kind: 'deposit', amount: Number($('moneyAmt').value) });
$('btnWdr').onclick = () => post('money', { kind: 'withdraw', amount: Number($('moneyAmt').value) });
$('btnRobSave').onclick = () => post('saveOutfit', { kind: 'rob', grade: -1 });
$('btnClearLogs').onclick = () => post('clearLogs');

$('btnCreate').onclick = () => {
    const raw = $('gdays').value.trim();
    const daysVal = raw === '' ? 30 : Number(raw);
    post('create', {
        name: $('gname').value,
        label: $('glabel').value,
        days: isNaN(daysVal) ? 30 : Math.floor(daysVal)
    });
};

$('btnRenew').onclick = () => {
    if (!selected) return;
    post('renewGang', { gang: selected });
};

$('btnEnable').onclick = () => {
    if (!selected) return;
    post('setGangEnabled', { gang: selected, enabled: true });
};

$('btnDisable').onclick = () => {
    if (!selected) return;
    post('setGangEnabled', { gang: selected, enabled: false });
};

$('btnSetDays').onclick = () => {
    if (!selected) return;
    const raw = $('renewDays').value.trim();
    if (raw === '') return;
    const v = Number(raw);
    if (isNaN(v) || v < 0) return;
    post('setGangRenewDays', { gang: selected, days: Math.floor(v) });
};

document.querySelectorAll('[data-kind]').forEach((btn) => {
    btn.onclick = () => {
        if (!selected) return;
        post('setLocation', { gang: selected, kind: btn.dataset.kind });
    };
});

$('btnAddRank').onclick = () => {
    if (!selected) return;
    const g = gangs[selected];
    g.ranks = g.ranks || [];
    if (g.ranks.length >= maxRanks) return;
    let next = 0;
    const used = new Set(g.ranks.map((r) => r.grade));
    while (used.has(next)) next++;
    g.ranks.push({ grade: next, label: 'Rank ' + next });
    renderRanks(g);
};

$('btnSaveRanks').onclick = () => {
    if (!selected) return;
    post('saveRanks', { gang: selected, ranks: collectRanks() });
};

$('btnAddRecipe').onclick = () => {
    if (!selected) return;
    const box = $('recipeList');
    if (box.querySelectorAll('.recipe').length >= 10) return;
    box.appendChild(recipeEl({ label: '', result: '', resultCount: 1, time: 5, ingredients: [{ item: '', count: 1 }] }, 0));
};

$('btnSaveRecipes').onclick = () => {
    if (!selected) return;
    post('saveRecipes', { gang: selected, recipes: collectRecipes() });
};

$('btnDelete').onclick = () => {
    if (!selected) return;
    post('deleteGang', { gang: selected });
};

// Telegram handlers
const chatInput = $('chatInput');
const btnSend = $('btnSendChat');
const btnEmoji = $('btnEmoji');
const emojiPanel = $('emojiPanel');
const tgSearch = $('tgSearch');
const btnNewGroup = $('btnNewGroup');
const btnNewGroupFab = $('btnNewGroupFab');
const groupModal = $('groupModal');
const btnCreateGroup = $('btnCreateGroup');
const btnCancelGroup = $('btnCancelGroup');

if (btnSend) {
    btnSend.onclick = () => {
        const msg = chatInput.value.trim();
        if (!msg) return;
        if (selectedChatType === 'group' && selectedGroupId) {
            post('sendGroupChat', { groupId: selectedGroupId, message: msg });
        } else if (selectedNegotiationGang) {
            post('sendChat', { target: selectedNegotiationGang, message: msg });
        } else {
            return;
        }
        chatInput.value = '';
    };
}
if (chatInput) {
    chatInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            if (btnSend) btnSend.click();
        }
    });
}
if (btnEmoji && emojiPanel) {
    btnEmoji.onclick = (e) => {
        e.stopPropagation();
        emojiPanel.classList.toggle('hidden');
    };
    emojiPanel.querySelectorAll('span').forEach(span => {
        span.onclick = () => {
            chatInput.value += span.textContent;
            chatInput.focus();
        };
    });
    document.addEventListener('click', (e) => {
        if (!emojiPanel.contains(e.target) && e.target !== btnEmoji) {
            emojiPanel.classList.add('hidden');
        }
    });
}
if (tgSearch) {
    tgSearch.addEventListener('input', () => {
        renderNegotiationGangs();
        renderGroups();
    });
}
function openGroupSheet() {
    renderGroupSelect();
    if (groupModal) groupModal.classList.remove('hidden');
}
function closeGroupSheet() {
    if (groupModal) groupModal.classList.add('hidden');
}
function openGroupProfile() {
    if (selectedChatType !== 'group' || !selectedGroupId) return;
    const gg = (allGroups || []).find(x => x.id === selectedGroupId);
    if (!gg) return;
    const modal = $('groupProfileModal');
    if (!modal) return;
    const av = $('groupProfileAvatar');
    const nameEl = $('groupProfileName');
    const subEl = $('groupProfileSub');
    const membersBox = $('groupProfileMembers');
    const btnDel = $('btnDeleteGroup');
    const btnLeave = $('btnLeaveGroup');
    if (av) av.textContent = getAvatarLetter(gg.label);
    if (nameEl) nameEl.textContent = gg.label;
    if (subEl) subEl.textContent = gg.name + ' • ' + (gg.members ? gg.members.length + ' members' : '');
    if (membersBox) {
        membersBox.innerHTML = '';
        (gg.members || []).forEach(m => {
            const label = (gg.memberLabels && gg.memberLabels[m]) || m;
            const isCreator = gg.creator_gang === m;
            const div = document.createElement('div');
            div.className = 'member-item';
            div.innerHTML = `<span class="av">${getAvatarLetter(label)}</span><div><b>${escapeHtml(label)} ${isCreator?'<small style=\"color:#2AABEE\">(creator)</small>':''}</b><small>${escapeHtml(m)}</small></div>`;
            membersBox.appendChild(div);
        });
    }
    const myGang = bossData?.gang?.name;
    const isCreator = gg.creator_gang === myGang;
    if (btnDel) {
        if (isCreator) { btnDel.classList.remove('hidden'); } else { btnDel.classList.add('hidden'); }
    }
    if (btnLeave) {
        if (!isCreator) { btnLeave.classList.remove('hidden'); } else { btnLeave.classList.add('hidden'); }
    }
    modal.classList.remove('hidden');
}
function closeGroupProfile() {
    const modal = $('groupProfileModal');
    if (modal) modal.classList.add('hidden');
}
function openDirectProfile() {
    if (selectedChatType !== 'direct' || !selectedNegotiationGang) return;
    const allGangsObj = getAllGangsForUI();
    const gg = allGangsObj[selectedNegotiationGang];
    if (!gg) return;
    const modal = $('directProfileModal');
    if (!modal) return;
    const av = $('directProfileAvatar');
    const nameEl = $('directProfileName');
    const subEl = $('directProfileSub');
    const statusEl = $('directProfileStatus');
    const btnBlock = $('btnBlockGang');
    const btnUnblock = $('btnUnblockGang');
    if (av) av.textContent = getAvatarLetter(gg.label);
    if (nameEl) nameEl.textContent = gg.label;
    if (subEl) subEl.textContent = gg.name;
    const isBlocked = blockedMap && blockedMap[gg.name];
    const isBlockedBy = blockedByMap && blockedByMap[gg.name];
    if (statusEl) {
        let html = `<b>${escapeHtml(gg.label)}</b><br><small style="color:#7d8b99">${escapeHtml(gg.name)}</small>`;
        if (isBlocked) html += '<br><span class="blocked-badge">You blocked this gang</span>';
        if (isBlockedBy) html += '<br><span class="blocked-badge" style="background:#ff9500">This gang blocked you</span>';
        statusEl.innerHTML = html;
    }
    if (btnBlock && btnUnblock) {
        if (isBlocked) {
            btnBlock.classList.add('hidden');
            btnUnblock.classList.remove('hidden');
        } else {
            btnBlock.classList.remove('hidden');
            btnUnblock.classList.add('hidden');
        }
    }
    modal.classList.remove('hidden');
}
function closeDirectProfile() {
    const modal = $('directProfileModal');
    if (modal) modal.classList.add('hidden');
}
if (btnNewGroup) {
    btnNewGroup.onclick = () => openGroupSheet();
}
if (btnNewGroupFab) {
    btnNewGroupFab.onclick = (e) => {
        e.stopPropagation();
        openGroupSheet();
    };
}
if (btnCancelGroup) {
    btnCancelGroup.onclick = () => closeGroupSheet();
}
if (btnCreateGroup) {
    btnCreateGroup.onclick = () => {
        const name = $('groupName').value.trim();
        const label = $('groupLabel').value.trim();
        const checks = [...document.querySelectorAll('#groupGangSelect input[type=checkbox]:checked')].map(c => c.value);
        if (!name || !label) return;
        post('createGroup', { name, label, members: checks });
        closeGroupSheet();
        $('groupName').value = '';
        $('groupLabel').value = '';
    };
}
// Profile header click
const chatHeader = $('chatHeader');
if (chatHeader) {
    chatHeader.onclick = () => {
        if (selectedChatType === 'group') openGroupProfile();
        else if (selectedChatType === 'direct') openDirectProfile();
    };
}
// Group profile buttons
const btnCloseGroupProfile = $('btnCloseGroupProfile');
const btnDeleteGroup = $('btnDeleteGroup');
const btnLeaveGroup = $('btnLeaveGroup');
if (btnCloseGroupProfile) btnCloseGroupProfile.onclick = () => closeGroupProfile();
if (btnDeleteGroup) {
    btnDeleteGroup.onclick = () => {
        if (selectedGroupId) {
            post('deleteGroup', { groupId: selectedGroupId });
            closeGroupProfile();
            selectedGroupId = null;
            selectedChatType = 'direct';
            $('chatHeaderTitle').textContent = 'Select a chat';
            $('chatHeaderSub').textContent = 'Telegram style negotiation';
            $('chatList').innerHTML = '';
        }
    };
}
if (btnLeaveGroup) {
    btnLeaveGroup.onclick = () => {
        if (selectedGroupId) {
            post('leaveGroup', { groupId: selectedGroupId });
            closeGroupProfile();
            selectedGroupId = null;
            selectedChatType = 'direct';
            $('chatHeaderTitle').textContent = 'Select a chat';
            $('chatHeaderSub').textContent = 'Telegram style negotiation';
            $('chatList').innerHTML = '';
        }
    };
}
// Direct profile buttons
const btnCloseDirectProfile = $('btnCloseDirectProfile');
const btnBlockGang = $('btnBlockGang');
const btnUnblockGang = $('btnUnblockGang');
if (btnCloseDirectProfile) btnCloseDirectProfile.onclick = () => closeDirectProfile();
if (btnBlockGang) {
    btnBlockGang.onclick = () => {
        if (selectedNegotiationGang) {
            post('blockGang', { target: selectedNegotiationGang });
            closeDirectProfile();
        }
    };
}
if (btnUnblockGang) {
    btnUnblockGang.onclick = () => {
        if (selectedNegotiationGang) {
            post('unblockGang', { target: selectedNegotiationGang });
            closeDirectProfile();
        }
    };
}
// Close modals when clicking outside
document.addEventListener('click', (e) => {
    const gpModal = $('groupProfileModal');
    const dpModal = $('directProfileModal');
    if (gpModal && !gpModal.classList.contains('hidden')) {
        if (e.target === gpModal) closeGroupProfile();
    }
    if (dpModal && !dpModal.classList.contains('hidden')) {
        if (e.target === dpModal) closeDirectProfile();
    }
    if (groupModal && !groupModal.classList.contains('hidden')) {
        const isFab = e.target === btnNewGroupFab || e.target === btnNewGroup;
        const inside = groupModal.contains(e.target);
        if (!inside && !isFab) {
            // keep open
        }
    }
});

document.addEventListener('click', () => {
    document.querySelectorAll('.manage.open').forEach((n) => n.classList.remove('open'));
});

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        const gpModal = $('groupProfileModal');
        const dpModal = $('directProfileModal');
        if (gpModal && !gpModal.classList.contains('hidden')) {
            closeGroupProfile();
        } else if (dpModal && !dpModal.classList.contains('hidden')) {
            closeDirectProfile();
        } else if (groupModal && !groupModal.classList.contains('hidden')) {
            closeGroupSheet();
        } else {
            hideAll();
            post('close');
        }
    }
});
