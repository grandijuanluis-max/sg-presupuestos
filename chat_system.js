// ====================================================================
// CHAT INTERNO, GRUPOS Y PRESENCIA EN TIEMPO REAL — SG MONTAJES SRL
// ====================================================================

(function() {
    'use strict';

    // Estado local del sistema de chat, grupos y presencia
    const ChatState = {
        currentUser: null,
        onlineUsers: new Map(), // key -> { id, username, role, email, onlineAt }
        presenceChannel: null,
        chatChannel: null,
        dbChannel: null,
        heartbeatTimer: null,
        messages: [], // Array de mensajes
        groups: [],   // Array de grupos { id, name, createdBy, createdAt, members: [userId1, ...] }
        activeConversationId: 'general', // 'general', userId (para DM), o groupId (para Grupo)
        activeConversationType: 'general', // 'general', 'dm', 'group'
        unreadCount: 0,
        unreadPerConv: {}, // convKey -> count
        isOpen: false,
        currentView: 'chat', // 'conversations', 'chat', 'create_group'
        isSoundEnabled: true
    };

    // --- REPRODUCTOR DE SONIDO CON WEB AUDIO API ---
    function playNotificationSound() {
        if (!ChatState.isSoundEnabled) return;
        try {
            const AudioContext = window.AudioContext || window.webkitAudioContext;
            if (!AudioContext) return;
            const ctx = new AudioContext();
            const now = ctx.currentTime;
            const osc = ctx.createOscillator();
            const gain = ctx.createGain();

            osc.type = 'sine';
            osc.frequency.setValueAtTime(587.33, now); // D5
            osc.frequency.setValueAtTime(880, now + 0.08); // A5

            gain.gain.setValueAtTime(0.12, now);
            gain.gain.exponentialRampToValueAtTime(0.001, now + 0.35);

            osc.connect(gain);
            gain.connect(ctx.destination);

            osc.start(now);
            osc.stop(now + 0.36);
        } catch (e) {}
    }

    // --- OBTENER CLIENTE SUPABASE ---
    function getSupabase() {
        if (window.supabaseDb) return window.supabaseDb;
        if (typeof window.initSupabaseClient === 'function') return window.initSupabaseClient();
        return null;
    }

    // --- ASEGURAR Y RESOLVER USUARIO ACTUAL ---
    function resolveCurrentUser() {
        if (ChatState.currentUser && ChatState.currentUser.id) {
            return ChatState.currentUser;
        }
        let found = null;
        if (typeof window.getCurrentUser === 'function') {
            found = window.getCurrentUser();
        }
        if (!found && typeof appData !== 'undefined' && appData && appData.currentUserId) {
            const users = getAllUsers();
            found = users.find(u => String(u.id) === String(appData.currentUserId));
        }
        if (found) {
            ChatState.currentUser = {
                id: String(found.id || found.username),
                username: String(found.username || 'Usuario').trim(),
                role: String(found.role || 'Solicitante').trim(),
                email: String(found.email || '').trim()
            };
        }
        return ChatState.currentUser;
    }

    // --- INICIALIZAR O REFRESCAR SESIÓN DEL USUARIO ---
    function setUser(user) {
        if (!user) {
            leavePresence();
            ChatState.currentUser = null;
            updateOnlinePillUI();
            closeChat();
            return;
        }

        const prevId = ChatState.currentUser ? String(ChatState.currentUser.id) : null;
        ChatState.currentUser = {
            id: String(user.id || user.username),
            username: String(user.username || 'Usuario').trim(),
            role: String(user.role || 'Solicitante').trim(),
            email: String(user.email || '').trim()
        };

        if (prevId !== ChatState.currentUser.id) {
            initPresence();
            initChatChannels();
            loadMessagesFromDb();
            loadGroupsFromDb();
        }
        updateOnlinePillUI();
        renderAllChatViews();
    }

    // --- PRESENCIA EN TIEMPO REAL (SUPABASE REALTIME PRESENCE) ---
    function initPresence() {
        const client = getSupabase();
        const user = resolveCurrentUser();
        if (!client || !user) return;

        try {
            if (ChatState.presenceChannel) {
                client.removeChannel(ChatState.presenceChannel);
                ChatState.presenceChannel = null;
            }

            const userKey = 'usr_' + user.id;
            ChatState.presenceChannel = client.channel('sg_montajes_presence', {
                config: { presence: { key: userKey } }
            });

            ChatState.presenceChannel
                .on('presence', { event: 'sync' }, () => {
                    handlePresenceSync();
                })
                .on('presence', { event: 'join' }, ({ key, newPresences }) => {
                    handlePresenceSync();
                })
                .on('presence', { event: 'leave' }, ({ key, leftPresences }) => {
                    handlePresenceSync();
                })
                .subscribe(async (status) => {
                    if (status === 'SUBSCRIBED') {
                        const cur = resolveCurrentUser();
                        if (cur) {
                            try {
                                await ChatState.presenceChannel.track({
                                    id: cur.id,
                                    username: cur.username,
                                    role: cur.role,
                                    email: cur.email,
                                    onlineAt: new Date().toISOString()
                                });
                            } catch (e) {}
                        }
                    }
                });

            // Heartbeat de presencia cada 25 segundos
            if (ChatState.heartbeatTimer) clearInterval(ChatState.heartbeatTimer);
            ChatState.heartbeatTimer = setInterval(async () => {
                const cur = resolveCurrentUser();
                if (ChatState.presenceChannel && cur) {
                    try {
                        await ChatState.presenceChannel.track({
                            id: cur.id,
                            username: cur.username,
                            role: cur.role,
                            email: cur.email,
                            onlineAt: new Date().toISOString()
                        });
                    } catch (e) {}
                }
            }, 25000);

        } catch (e) {
            console.error('Error al iniciar presencia Supabase:', e);
        }
    }

    function leavePresence() {
        const client = getSupabase();
        if (ChatState.heartbeatTimer) {
            clearInterval(ChatState.heartbeatTimer);
            ChatState.heartbeatTimer = null;
        }
        if (ChatState.presenceChannel) {
            try {
                ChatState.presenceChannel.untrack();
                if (client) client.removeChannel(ChatState.presenceChannel);
            } catch (e) {}
            ChatState.presenceChannel = null;
        }
        ChatState.onlineUsers.clear();
        updateOnlinePillUI();
    }

    function handlePresenceSync() {
        if (!ChatState.presenceChannel) return;
        const state = ChatState.presenceChannel.presenceState();
        ChatState.onlineUsers.clear();

        Object.keys(state).forEach(key => {
            const presences = state[key];
            if (Array.isArray(presences) && presences.length > 0) {
                const latest = presences[presences.length - 1];
                if (latest && latest.id) {
                    ChatState.onlineUsers.set(String(latest.id), latest);
                }
            }
        });

        const cur = resolveCurrentUser();
        if (cur) {
            ChatState.onlineUsers.set(String(cur.id), {
                id: cur.id,
                username: cur.username,
                role: cur.role,
                email: cur.email,
                onlineAt: new Date().toISOString()
            });
        }

        updateOnlinePillUI();
        renderOnlineDropdownList();
        renderConversationsList();
        renderChatHeader();
    }

    // --- CANALES REALTIME (BROADCAST + POSTGRES SYNC) ---
    function initChatChannels() {
        const client = getSupabase();
        if (!client) return;

        try {
            if (ChatState.chatChannel) {
                client.removeChannel(ChatState.chatChannel);
                ChatState.chatChannel = null;
            }

            ChatState.chatChannel = client
                .channel('sg_montajes_chat')
                .on('broadcast', { event: 'new_message' }, ({ payload }) => {
                    handleIncomingMessage(payload);
                })
                .on('broadcast', { event: 'new_group' }, ({ payload }) => {
                    handleIncomingGroup(payload);
                })
                .on('broadcast', { event: 'typing' }, ({ payload }) => {
                    handleTypingIndicator(payload);
                })
                .subscribe();

            // Suscripción a la tabla notificaciones
            if (ChatState.dbChannel) {
                client.removeChannel(ChatState.dbChannel);
                ChatState.dbChannel = null;
            }
            ChatState.dbChannel = client
                .channel('public:notificaciones_chat')
                .on('postgres_changes', {
                    event: 'INSERT',
                    schema: 'public',
                    table: 'notificaciones'
                }, (payload) => {
                    if (payload.new && payload.new.message) {
                        try {
                            const parsed = JSON.parse(payload.new.message);
                            if (payload.new.task_id === 'internal_chat') {
                                handleIncomingMessage(parsed);
                            } else if (payload.new.task_id === 'internal_chat_groups') {
                                handleIncomingGroup(parsed);
                            }
                        } catch (e) {}
                    }
                })
                .subscribe();

        } catch (e) {
            console.error('Error al inicializar canales de chat Supabase:', e);
        }
    }

    // --- CARGAR HISTORIAL DE MENSAJES Y GRUPOS DESDE SUPABASE ---
    async function loadMessagesFromDb() {
        try {
            const cached = localStorage.getItem('sg_chat_messages_history');
            if (cached) {
                const parsed = JSON.parse(cached);
                if (Array.isArray(parsed)) {
                    ChatState.messages = parsed;
                    renderMessages();
                }
            }
        } catch (e) {}

        const client = getSupabase();
        if (!client) return;

        try {
            const { data } = await client
                .from('notificaciones')
                .select('*')
                .eq('task_id', 'internal_chat')
                .order('timestamp', { ascending: true })
                .limit(250);

            if (data && Array.isArray(data)) {
                const loaded = [];
                data.forEach(row => {
                    try {
                        const msg = typeof row.message === 'string' ? JSON.parse(row.message) : row.message;
                        if (msg && msg.id && msg.text) {
                            if (!msg.timestamp && row.timestamp) msg.timestamp = row.timestamp;
                            loaded.push(msg);
                        }
                    } catch (e) {}
                });

                if (loaded.length > 0) {
                    mergeMessages(loaded);
                    saveMessagesToLocal();
                    renderMessages();
                }
            }
        } catch (err) {
            console.warn('Aviso cargando mensajes de Supabase:', err);
        }
    }

    async function loadGroupsFromDb() {
        try {
            const cached = localStorage.getItem('sg_chat_groups_list');
            if (cached) {
                const parsed = JSON.parse(cached);
                if (Array.isArray(parsed)) {
                    ChatState.groups = parsed;
                    renderConversationsList();
                }
            }
        } catch (e) {}

        const client = getSupabase();
        if (!client) return;

        try {
            const { data } = await client
                .from('notificaciones')
                .select('*')
                .eq('task_id', 'internal_chat_groups')
                .order('timestamp', { ascending: true });

            if (data && Array.isArray(data)) {
                const loadedGroups = [];
                data.forEach(row => {
                    try {
                        const grp = typeof row.message === 'string' ? JSON.parse(row.message) : row.message;
                        if (grp && grp.id && grp.name) {
                            loadedGroups.push(grp);
                        }
                    } catch (e) {}
                });

                if (loadedGroups.length > 0) {
                    mergeGroups(loadedGroups);
                    saveGroupsToLocal();
                    renderConversationsList();
                }
            }
        } catch (err) {
            console.warn('Aviso cargando grupos de Supabase:', err);
        }
    }

    function mergeMessages(newMsgs) {
        const map = new Map();
        ChatState.messages.forEach(m => map.set(m.id, m));
        newMsgs.forEach(m => map.set(m.id, m));
        ChatState.messages = Array.from(map.values()).sort((a, b) => {
            return new Date(a.timestamp || 0) - new Date(b.timestamp || 0);
        });
    }

    function mergeGroups(newGroups) {
        const map = new Map();
        ChatState.groups.forEach(g => map.set(g.id, g));
        newGroups.forEach(g => map.set(g.id, g));
        ChatState.groups = Array.from(map.values());
    }

    function saveMessagesToLocal() {
        try {
            const toSave = ChatState.messages.slice(-200);
            localStorage.setItem('sg_chat_messages_history', JSON.stringify(toSave));
        } catch (e) {}
    }

    function saveGroupsToLocal() {
        try {
            localStorage.setItem('sg_chat_groups_list', JSON.stringify(ChatState.groups));
        } catch (e) {}
    }

    // --- PROCESAMIENTO DE MENSAJES Y GRUPOS ENTRANTES ---
    function handleIncomingMessage(msg) {
        if (!msg || !msg.id || !msg.text) return;

        const exists = ChatState.messages.some(m => m.id === msg.id);
        if (exists) return;

        ChatState.messages.push(msg);
        saveMessagesToLocal();

        const cur = resolveCurrentUser();
        const myId = cur ? String(cur.id) : '';
        const isFromMe = myId && String(msg.senderId) === myId;

        // Determinar clave de conversación
        let convKey = 'general';
        if (msg.type === 'dm' || msg.channel === 'dm') {
            convKey = String(msg.senderId) === myId ? String(msg.recipientId) : String(msg.senderId);
        } else if (msg.type === 'group' || msg.channel === 'group') {
            convKey = 'group_' + (msg.groupId || '');
        }

        const isCurrentActive = 
            ChatState.isOpen && 
            ChatState.currentView === 'chat' && 
            ((ChatState.activeConversationType === 'general' && convKey === 'general') ||
             (ChatState.activeConversationType === 'dm' && String(ChatState.activeConversationId) === convKey) ||
             (ChatState.activeConversationType === 'group' && 'group_' + String(ChatState.activeConversationId) === convKey));

        if (!isFromMe) {
            playNotificationSound();

            if (!isCurrentActive) {
                ChatState.unreadCount++;
                updateUnreadBadge();

                ChatState.unreadPerConv[convKey] = (ChatState.unreadPerConv[convKey] || 0) + 1;
                renderConversationsList();

                if (typeof window.showToast === 'function') {
                    const senderLabel = msg.senderUsername || 'Un colega';
                    const previewText = msg.text.length > 50 ? msg.text.substring(0, 47) + '...' : msg.text;
                    let prefix = '#General';
                    if (msg.type === 'dm') prefix = 'Mensaje directo';
                    else if (msg.type === 'group') prefix = `Grupo ${msg.groupName || ''}`;
                    window.showToast(`💬 ${senderLabel} (${prefix}): ${previewText}`, 'info');
                }
            }
        }

        renderMessages();
    }

    function handleIncomingGroup(group) {
        if (!group || !group.id || !group.name) return;
        const exists = ChatState.groups.some(g => g.id === group.id);
        if (!exists) {
            ChatState.groups.push(group);
            saveGroupsToLocal();
            renderConversationsList();
            if (typeof window.showToast === 'function') {
                window.showToast(`👥 Nuevo grupo de chat: "${group.name}"`, 'info');
            }
        }
    }

    // --- ENVIAR MENSAJE ---
    async function sendMessage(text) {
        if (!text || !text.trim()) return;
        const cleanText = text.trim();
        const cur = resolveCurrentUser();
        if (!cur) {
            if (typeof window.showToast === 'function') {
                window.showToast('Debés iniciar sesión para enviar mensajes.', 'error');
            }
            return;
        }

        const type = ChatState.activeConversationType;
        const activeId = ChatState.activeConversationId;

        let recipientUser = null;
        let targetGroup = null;

        if (type === 'dm') {
            recipientUser = getAllUsers().find(u => String(u.id) === String(activeId));
        } else if (type === 'group') {
            targetGroup = ChatState.groups.find(g => String(g.id) === String(activeId));
        }

        const messageObj = {
            id: 'MSG-' + Date.now() + '-' + Math.random().toString(36).substr(2, 6),
            type: type, // 'general', 'dm', 'group'
            channel: type,
            senderId: String(cur.id),
            senderUsername: cur.username,
            senderRole: cur.role,
            recipientId: type === 'dm' ? String(activeId) : (type === 'group' ? 'group_' + activeId : 'all'),
            recipientUsername: recipientUser ? recipientUser.username : '',
            groupId: type === 'group' ? String(activeId) : null,
            groupName: targetGroup ? targetGroup.name : null,
            text: cleanText,
            timestamp: new Date().toISOString()
        };

        // 1. Agregar de inmediato a la UI local
        ChatState.messages.push(messageObj);
        saveMessagesToLocal();
        renderMessages();

        // 2. Broadcast instantáneo por Supabase Realtime
        if (ChatState.chatChannel) {
            try {
                ChatState.chatChannel.send({
                    type: 'broadcast',
                    event: 'new_message',
                    payload: messageObj
                });
            } catch (err) {
                console.warn('Aviso broadcast chat:', err);
            }
        }

        // 3. Persistir permanentemente en base de datos Supabase
        const client = getSupabase();
        if (client) {
            try {
                client.from('notificaciones').insert([{
                    id: messageObj.id,
                    message: JSON.stringify(messageObj),
                    read: false,
                    task_id: 'internal_chat'
                }]).then(res => {
                    if (res.error) console.warn('Aviso guardando mensaje en Supabase:', res.error);
                }).catch(e => {
                    console.warn('Error guardando en Supabase:', e);
                });
            } catch (e) {}
        }
    }

    // --- CREAR NUEVO GRUPO DE CHAT ---
    async function createGroup(groupName, memberIds) {
        if (!groupName || !groupName.trim()) {
            if (typeof window.showToast === 'function') window.showToast('Ingresá un nombre para el grupo.', 'warning');
            return;
        }
        const cur = resolveCurrentUser();
        if (!cur) return;

        const cleanName = groupName.trim();
        // Asegurar que el creador esté en la lista de miembros
        const finalMembers = Array.from(new Set([String(cur.id), ...(memberIds || []).map(String)]));

        const newGroup = {
            id: 'GRP-' + Date.now() + '-' + Math.random().toString(36).substr(2, 5),
            name: cleanName,
            createdBy: cur.username,
            createdById: String(cur.id),
            createdAt: new Date().toISOString(),
            members: finalMembers
        };

        // 1. Guardar localmente
        ChatState.groups.push(newGroup);
        saveGroupsToLocal();

        // 2. Broadcast a todos los conectados
        if (ChatState.chatChannel) {
            try {
                ChatState.chatChannel.send({
                    type: 'broadcast',
                    event: 'new_group',
                    payload: newGroup
                });
            } catch (e) {}
        }

        // 3. Persistir en Supabase
        const client = getSupabase();
        if (client) {
            try {
                client.from('notificaciones').insert([{
                    id: 'GROUP_' + newGroup.id,
                    message: JSON.stringify(newGroup),
                    read: false,
                    task_id: 'internal_chat_groups'
                }]).then(res => {
                    if (res.error) console.warn('Aviso guardando grupo en Supabase:', res.error);
                }).catch(e => console.warn('Error guardando grupo:', e));
            } catch (e) {}
        }

        if (typeof window.showToast === 'function') {
            window.showToast(`Grupo "${cleanName}" creado con éxito.`, 'success');
        }

        // Abrir inmediatamente la conversación con el nuevo grupo
        openGroupChat(newGroup.id);
    }

    // --- INDICADOR DE USUARIO ESCRIBIENDO ---
    let typingTimeout = null;
    function notifyTyping() {
        const cur = resolveCurrentUser();
        if (!ChatState.chatChannel || !cur) return;
        try {
            ChatState.chatChannel.send({
                type: 'broadcast',
                event: 'typing',
                payload: {
                    userId: cur.id,
                    username: cur.username,
                    convId: ChatState.activeConversationId,
                    convType: ChatState.activeConversationType
                }
            });
        } catch (e) {}
    }

    function handleTypingIndicator(payload) {
        const cur = resolveCurrentUser();
        if (!payload || !cur || String(payload.userId) === String(cur.id)) return;

        const isMatch = 
            payload.convType === ChatState.activeConversationType && 
            String(payload.convId) === String(ChatState.activeConversationId);

        if (isMatch) {
            const typingEl = document.getElementById('sg-chat-typing-indicator');
            if (typingEl) {
                typingEl.innerText = `${payload.username} está escribiendo...`;
                typingEl.style.display = 'block';
                if (typingTimeout) clearTimeout(typingTimeout);
                typingTimeout = setTimeout(() => {
                    typingEl.style.display = 'none';
                }, 2500);
            }
        }
    }

    // --- LISTA DE USUARIOS DEL SISTEMA ---
    function getAllUsers() {
        let users = [];
        if (typeof appData !== 'undefined' && appData && Array.isArray(appData.users) && appData.users.length > 0) {
            users = appData.users;
        } else if (typeof defaultData !== 'undefined' && defaultData && Array.isArray(defaultData.users)) {
            users = defaultData.users;
        }
        return users.filter(u => u && !['admin', 'aut', 'sol'].includes(String(u.username).trim().toLowerCase()));
    }

    // --- UI: INDICADOR DE USUARIOS EN LÍNEA EN EL HEADER ---
    function updateOnlinePillUI() {
        const countEl = document.getElementById('online-users-count');
        const pillEl = document.getElementById('online-users-pill');
        const widgetEl = document.getElementById('sg-chat-widget');

        const cur = resolveCurrentUser();
        if (!cur) {
            if (pillEl) pillEl.style.display = 'none';
            if (widgetEl) widgetEl.style.display = 'none';
            return;
        }

        if (pillEl) pillEl.style.display = 'inline-flex';
        if (widgetEl) widgetEl.style.display = 'block';

        if (countEl) {
            const totalOnline = Math.max(1, ChatState.onlineUsers.size);
            countEl.innerText = totalOnline === 1 ? '1 en línea' : `${totalOnline} en línea`;
        }
    }

    function renderOnlineDropdownList() {
        const dropdownList = document.getElementById('online-users-dropdown-list');
        if (!dropdownList) return;

        const allUsers = getAllUsers();
        if (allUsers.length === 0) {
            dropdownList.innerHTML = '<div style="padding: 12px; text-align: center; color: var(--text-muted); font-size: 12px;">No hay usuarios registrados</div>';
            return;
        }

        let html = '';
        const onlineList = [];
        const offlineList = [];
        const cur = resolveCurrentUser();

        allUsers.forEach(user => {
            const isOnline = ChatState.onlineUsers.has(String(user.id)) || (cur && String(user.id) === String(cur.id));
            if (isOnline) onlineList.push(user);
            else offlineList.push(user);
        });

        // En línea
        html += `<div style="font-size: 11px; font-weight: 700; color: #10b981; text-transform: uppercase; padding: 6px 10px; letter-spacing: 0.5px; display: flex; align-items: center; gap: 6px;">
            <span style="display: inline-block; width: 8px; height: 8px; border-radius: 50%; background: #10b981; box-shadow: 0 0 8px #10b981;"></span>
            En línea (${onlineList.length})
        </div>`;

        onlineList.forEach(user => {
            const isMe = cur && String(user.id) === String(cur.id);
            const initials = getInitials(user.username);
            const roleColor = getRoleBadgeColor(user.role);

            html += `
                <div class="user-item-row" style="display: flex; align-items: center; justify-content: space-between; padding: 8px 10px; border-radius: 8px; margin-bottom: 4px; transition: background 0.2s;">
                    <div style="display: flex; align-items: center; gap: 10px;">
                        <div class="avatar-badge" style="position: relative;">
                            <span style="display: flex; align-items: center; justify-content: center; width: 32px; height: 32px; border-radius: 50%; background: #1e3a8a; color: white; font-weight: 700; font-size: 12px; border: 1.5px solid #38bdf8;">${initials}</span>
                            <span style="position: absolute; bottom: -1px; right: -1px; width: 10px; height: 10px; background: #10b981; border: 2px solid #0f172a; border-radius: 50%;"></span>
                        </div>
                        <div>
                            <div style="font-size: 13px; font-weight: 700; color: #ffffff;">${user.username} ${isMe ? '<span style="font-size: 10px; color: var(--warning); font-weight: normal;">(Tú)</span>' : ''}</div>
                            <span style="font-size: 10px; padding: 1px 6px; border-radius: 4px; background: ${roleColor.bg}; color: ${roleColor.color}; font-weight: 600;">${user.role || 'Solicitante'}</span>
                        </div>
                    </div>
                    ${!isMe ? `
                        <button type="button" class="btn btn-sm" onclick="window.SGChat.openChatWith('${user.id}')" style="background: rgba(37,99,235,0.25); border: 1px solid #2563eb; color: #93c5fd; font-size: 11px; padding: 4px 8px; border-radius: 6px; cursor: pointer; display: flex; align-items: center; gap: 4px;">
                            <i class="fas fa-comment-dots"></i> Chatear
                        </button>
                    ` : ''}
                </div>
            `;
        });

        // Desconectados
        if (offlineList.length > 0) {
            html += `<div style="font-size: 11px; font-weight: 700; color: var(--text-muted); text-transform: uppercase; padding: 10px 10px 6px 10px; letter-spacing: 0.5px; display: flex; align-items: center; gap: 6px; border-top: 1px solid rgba(255,255,255,0.08); margin-top: 6px;">
                <span style="display: inline-block; width: 8px; height: 8px; border-radius: 50%; background: #64748b;"></span>
                Desconectados (${offlineList.length})
            </div>`;

            offlineList.forEach(user => {
                const initials = getInitials(user.username);
                const roleColor = getRoleBadgeColor(user.role);

                html += `
                    <div class="user-item-row" style="display: flex; align-items: center; justify-content: space-between; padding: 6px 10px; border-radius: 8px; margin-bottom: 4px; opacity: 0.75;">
                        <div style="display: flex; align-items: center; gap: 10px;">
                            <div class="avatar-badge" style="position: relative;">
                                <span style="display: flex; align-items: center; justify-content: center; width: 30px; height: 30px; border-radius: 50%; background: #334155; color: #cbd5e1; font-weight: 600; font-size: 11px;">${initials}</span>
                                <span style="position: absolute; bottom: -1px; right: -1px; width: 8px; height: 8px; background: #64748b; border: 1.5px solid #0f172a; border-radius: 50%;"></span>
                            </div>
                            <div>
                                <div style="font-size: 12px; font-weight: 600; color: var(--text-muted);">${user.username}</div>
                                <span style="font-size: 9px; padding: 1px 5px; border-radius: 4px; background: ${roleColor.bg}; color: ${roleColor.color}; font-weight: 500;">${user.role || 'Solicitante'}</span>
                            </div>
                        </div>
                        <button type="button" class="btn btn-sm" onclick="window.SGChat.openChatWith('${user.id}')" style="background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.15); color: #cbd5e1; font-size: 10px; padding: 3px 6px; border-radius: 5px; cursor: pointer;">
                            Mensaje
                        </button>
                    </div>
                `;
            });
        }

        dropdownList.innerHTML = html;
    }

    // --- UI: NAVEGACIÓN Y APERTURA DE CHAT ---
    function toggleChat() {
        if (ChatState.isOpen) closeChat();
        else openChat();
    }

    function openChat() {
        const cur = resolveCurrentUser();
        if (!cur) {
            if (typeof window.showToast === 'function') {
                window.showToast('Debés iniciar sesión para utilizar el chat interno.', 'warning');
            }
            return;
        }

        ChatState.isOpen = true;
        const win = document.getElementById('sg-chat-window');
        const btn = document.getElementById('sg-chat-toggle-btn');
        if (win) win.style.display = 'flex';
        if (btn) btn.classList.add('chat-open');

        // Mostrar vista actual (por defecto conversación abierta o selector)
        switchView(ChatState.currentView || 'chat');
    }

    function closeChat() {
        ChatState.isOpen = false;
        const win = document.getElementById('sg-chat-window');
        const btn = document.getElementById('sg-chat-toggle-btn');
        if (win) win.style.display = 'none';
        if (btn) btn.classList.remove('chat-open');
    }

    // Control central de vistas dentro de la ventana de chat
    function switchView(viewName) {
        ChatState.currentView = viewName; // 'chat', 'conversations', 'create_group'

        const chatPane = document.getElementById('sg-chat-messages-pane');
        const footerPane = document.getElementById('sg-chat-footer');
        const convsPane = document.getElementById('sg-chat-contacts-pane');
        const createGroupPane = document.getElementById('sg-chat-create-group-pane');
        const backBtn = document.getElementById('sg-chat-back-btn');
        const convListBtn = document.getElementById('sg-chat-list-toggle-btn');

        if (viewName === 'conversations') {
            if (chatPane) chatPane.style.display = 'none';
            if (footerPane) footerPane.style.display = 'none';
            if (createGroupPane) createGroupPane.style.display = 'none';
            if (convsPane) convsPane.style.display = 'block';
            if (backBtn) backBtn.style.display = 'none';
            if (convListBtn) convListBtn.style.display = 'none';
            renderConversationsList();
            renderChatHeader();
        } else if (viewName === 'create_group') {
            if (chatPane) chatPane.style.display = 'none';
            if (footerPane) footerPane.style.display = 'none';
            if (convsPane) convsPane.style.display = 'none';
            if (createGroupPane) createGroupPane.style.display = 'flex';
            if (backBtn) backBtn.style.display = 'inline-flex';
            if (convListBtn) convListBtn.style.display = 'none';
            renderCreateGroupForm();
            renderChatHeader();
        } else {
            // 'chat'
            if (convsPane) convsPane.style.display = 'none';
            if (createGroupPane) createGroupPane.style.display = 'none';
            if (chatPane) chatPane.style.display = 'flex';
            if (footerPane) footerPane.style.display = 'flex'; // SIEMPRE VISIBLE EN VISTA CHAT
            if (backBtn) backBtn.style.display = 'inline-flex';
            if (convListBtn) convListBtn.style.display = 'inline-flex';
            clearActiveUnread();
            renderChatHeader();
            renderMessages();
            updateInputPlaceholder();

            setTimeout(() => {
                const input = document.getElementById('sg-chat-input');
                if (input) input.focus();
                scrollChatToBottom();
            }, 80);
        }
    }

    function openChatWith(userId) {
        ChatState.activeConversationId = String(userId);
        ChatState.activeConversationType = 'dm';
        openChat();
        switchView('chat');
    }

    function openGroupChat(groupId) {
        ChatState.activeConversationId = String(groupId);
        ChatState.activeConversationType = 'group';
        openChat();
        switchView('chat');
    }

    function openGeneralChat() {
        ChatState.activeConversationId = 'general';
        ChatState.activeConversationType = 'general';
        openChat();
        switchView('chat');
    }

    function showCreateGroupView() {
        switchView('create_group');
    }

    function showConversationsView() {
        switchView('conversations');
    }

    function clearActiveUnread() {
        let key = 'general';
        if (ChatState.activeConversationType === 'dm') {
            key = String(ChatState.activeConversationId);
        } else if (ChatState.activeConversationType === 'group') {
            key = 'group_' + String(ChatState.activeConversationId);
        }

        const count = ChatState.unreadPerConv[key] || 0;
        if (count > 0) {
            ChatState.unreadCount = Math.max(0, ChatState.unreadCount - count);
            ChatState.unreadPerConv[key] = 0;
            updateUnreadBadge();
        }
    }

    function updateUnreadBadge() {
        const badge = document.getElementById('sg-chat-unread-badge');
        if (!badge) return;
        if (ChatState.unreadCount > 0) {
            badge.innerText = ChatState.unreadCount > 99 ? '99+' : ChatState.unreadCount;
            badge.style.display = 'inline-flex';
        } else {
            badge.style.display = 'none';
        }
    }

    // --- RENDER DE CABECERA DE CHAT ---
    function renderChatHeader() {
        const titleEl = document.getElementById('sg-chat-title');
        const subtitleEl = document.getElementById('sg-chat-subtitle');
        if (!titleEl || !subtitleEl) return;

        if (ChatState.currentView === 'conversations') {
            titleEl.innerHTML = '<i class="fa-solid fa-comments" style="color: #38bdf8; margin-right: 6px;"></i> Mensajería Interna';
            subtitleEl.innerText = 'Elegí un chat, un colega o creá un grupo';
            return;
        }

        if (ChatState.currentView === 'create_group') {
            titleEl.innerHTML = '<i class="fa-solid fa-users-gear" style="color: #fbbf24; margin-right: 6px;"></i> Crear Nuevo Grupo';
            subtitleEl.innerText = 'Definí el nombre y elegí los integrantes';
            return;
        }

        const cur = resolveCurrentUser();
        if (ChatState.activeConversationType === 'general') {
            titleEl.innerHTML = '<i class="fa-solid fa-users" style="color: #38bdf8; margin-right: 6px;"></i> # General (Equipo)';
            const onlineCount = ChatState.onlineUsers.size;
            subtitleEl.innerText = `${onlineCount} en línea ahora`;
        } else if (ChatState.activeConversationType === 'group') {
            const grp = ChatState.groups.find(g => String(g.id) === String(ChatState.activeConversationId));
            const groupName = grp ? grp.name : 'Grupo';
            const memberCount = grp && Array.isArray(grp.members) ? grp.members.length : 0;
            titleEl.innerHTML = `<i class="fa-solid fa-user-group" style="color: #fbbf24; margin-right: 6px;"></i> ${escapeHtml(groupName)}`;
            subtitleEl.innerText = `${memberCount} miembros`;
        } else {
            // Direct Message
            const targetUser = getAllUsers().find(u => String(u.id) === String(ChatState.activeConversationId));
            const isOnline = targetUser ? (ChatState.onlineUsers.has(String(targetUser.id)) || (cur && String(targetUser.id) === String(cur.id))) : false;
            const username = targetUser ? targetUser.username : 'Colega';
            const role = targetUser ? targetUser.role : '';
            titleEl.innerHTML = `<span style="display: inline-block; width: 9px; height: 9px; border-radius: 50%; background: ${isOnline ? '#10b981' : '#64748b'}; margin-right: 6px;"></span> ${escapeHtml(username)}`;
            subtitleEl.innerText = isOnline ? `🟢 En línea • ${role}` : `⚪ Desconectado • ${role}`;
        }
    }

    function updateInputPlaceholder() {
        const input = document.getElementById('sg-chat-input');
        if (!input) return;

        if (ChatState.activeConversationType === 'general') {
            input.placeholder = 'Escribe un mensaje para todo el equipo...';
        } else if (ChatState.activeConversationType === 'group') {
            const grp = ChatState.groups.find(g => String(g.id) === String(ChatState.activeConversationId));
            input.placeholder = `Escribe en ${grp ? grp.name : 'el grupo'}...`;
        } else {
            const targetUser = getAllUsers().find(u => String(u.id) === String(ChatState.activeConversationId));
            input.placeholder = `Escribe un mensaje privado a ${targetUser ? targetUser.username : 'colega'}...`;
        }
    }

    // --- RENDER DE LISTA DE CONVERSACIONES (CANAL, GRUPOS Y COLEGAS) ---
    function renderConversationsList() {
        const listEl = document.getElementById('sg-chat-contacts-list');
        if (!listEl) return;

        const cur = resolveCurrentUser();
        const myId = cur ? String(cur.id) : '';
        let html = '';

        // 1. CANAL GENERAL
        const unreadGen = ChatState.unreadPerConv['general'] || 0;
        const totalOnline = ChatState.onlineUsers.size;

        html += `
            <div class="chat-conv-item" onclick="window.SGChat.openGeneralChat()" style="display: flex; align-items: center; justify-content: space-between; padding: 10px 12px; border-radius: 10px; cursor: pointer; margin-bottom: 8px; background: rgba(37,99,235,0.18); border: 1px solid rgba(56,189,248,0.3); transition: all 0.2s;">
                <div style="display: flex; align-items: center; gap: 10px;">
                    <div style="width: 36px; height: 36px; border-radius: 50%; background: #1e3a8a; display: flex; align-items: center; justify-content: center; color: #38bdf8; font-size: 15px; border: 1.5px solid #38bdf8;">
                        <i class="fa-solid fa-users"></i>
                    </div>
                    <div>
                        <div style="font-size: 13px; font-weight: 800; color: #ffffff;"># General (Todo el equipo)</div>
                        <div style="font-size: 11px; color: #94a3b8;">${totalOnline} colegas conectados ahora</div>
                    </div>
                </div>
                ${unreadGen > 0 ? `
                    <span style="background: #ff3b30; color: white; font-size: 11px; font-weight: 800; padding: 2px 8px; border-radius: 12px;">${unreadGen}</span>
                ` : ''}
            </div>
        `;

        // 2. SECCIÓN GRUPOS (Con botón para crear nuevo)
        html += `
            <div style="display: flex; align-items: center; justify-content: space-between; margin: 14px 4px 6px 4px;">
                <span style="font-size: 11px; font-weight: 800; color: #fbbf24; text-transform: uppercase; letter-spacing: 0.5px; display: flex; align-items: center; gap: 6px;">
                    <i class="fa-solid fa-user-group"></i> Grupos de Trabajo (${ChatState.groups.length})
                </span>
                <button type="button" onclick="window.SGChat.showCreateGroupView()" style="background: rgba(251,191,36,0.18); border: 1px solid #fbbf24; color: #fde68a; font-size: 11px; font-weight: 700; padding: 3px 8px; border-radius: 6px; cursor: pointer; display: flex; align-items: center; gap: 4px; transition: all 0.2s;">
                    <i class="fas fa-plus"></i> Crear Grupo
                </button>
            </div>
        `;

        if (ChatState.groups.length === 0) {
            html += `
                <div style="padding: 10px 12px; background: rgba(255,255,255,0.03); border: 1px dashed rgba(255,255,255,0.15); border-radius: 8px; text-align: center; margin-bottom: 8px;">
                    <div style="font-size: 12px; color: var(--text-muted); margin-bottom: 4px;">No hay grupos creados todavía.</div>
                    <button type="button" onclick="window.SGChat.showCreateGroupView()" style="background: none; border: none; color: #38bdf8; font-size: 11px; font-weight: 700; cursor: pointer; text-decoration: underline;">
                        + Crear el primer grupo del equipo
                    </button>
                </div>
            `;
        } else {
            ChatState.groups.forEach(grp => {
                const unreadGrp = ChatState.unreadPerConv['group_' + grp.id] || 0;
                const memberCount = Array.isArray(grp.members) ? grp.members.length : 0;

                html += `
                    <div class="chat-conv-item" onclick="window.SGChat.openGroupChat('${grp.id}')" style="display: flex; align-items: center; justify-content: space-between; padding: 9px 12px; border-radius: 8px; cursor: pointer; margin-bottom: 4px; background: rgba(255,255,255,0.03); border: 1px solid rgba(251,191,36,0.25); transition: all 0.2s;">
                        <div style="display: flex; align-items: center; gap: 10px;">
                            <div style="width: 34px; height: 34px; border-radius: 50%; background: #3b2a05; display: flex; align-items: center; justify-content: center; color: #fbbf24; font-size: 13px; border: 1.5px solid #fbbf24;">
                                <i class="fa-solid fa-users-gear"></i>
                            </div>
                            <div>
                                <div style="font-size: 13px; font-weight: 700; color: #ffffff;">${escapeHtml(grp.name)}</div>
                                <div style="font-size: 11px; color: var(--text-muted);">${memberCount} miembros</div>
                            </div>
                        </div>
                        ${unreadGrp > 0 ? `
                            <span style="background: #ff3b30; color: white; font-size: 11px; font-weight: 800; padding: 2px 7px; border-radius: 12px;">${unreadGrp}</span>
                        ` : ''}
                    </div>
                `;
            });
        }

        // 3. SECCIÓN MENSAJES DIRECTOS (1 A 1)
        const allUsers = getAllUsers();
        html += `
            <div style="margin: 14px 4px 6px 4px; font-size: 11px; font-weight: 800; color: #38bdf8; text-transform: uppercase; letter-spacing: 0.5px; display: flex; align-items: center; gap: 6px;">
                <i class="fa-solid fa-user"></i> Mensajes Directos (1 a 1)
            </div>
        `;

        allUsers.forEach(user => {
            if (myId && String(user.id) === myId) return; // No mostrarse a sí mismo en DMs

            const isOnline = ChatState.onlineUsers.has(String(user.id));
            const unread = ChatState.unreadPerConv[String(user.id)] || 0;
            const initials = getInitials(user.username);
            const roleColor = getRoleBadgeColor(user.role);

            html += `
                <div class="chat-conv-item" onclick="window.SGChat.openChatWith('${user.id}')" style="display: flex; align-items: center; justify-content: space-between; padding: 8px 12px; border-radius: 8px; cursor: pointer; margin-bottom: 4px; transition: all 0.2s; background: rgba(255,255,255,0.02); border: 1px solid rgba(255,255,255,0.06);">
                    <div style="display: flex; align-items: center; gap: 10px;">
                        <div style="position: relative;">
                            <span style="display: flex; align-items: center; justify-content: center; width: 32px; height: 32px; border-radius: 50%; background: ${isOnline ? '#1e3a8a' : '#334155'}; color: ${isOnline ? '#ffffff' : '#94a3b8'}; font-weight: 700; font-size: 12px; border: 1.5px solid ${isOnline ? '#38bdf8' : '#475569'};">${initials}</span>
                            <span style="position: absolute; bottom: -1px; right: -1px; width: 9px; height: 9px; background: ${isOnline ? '#10b981' : '#64748b'}; border: 2px solid #0f172a; border-radius: 50%;"></span>
                        </div>
                        <div>
                            <div style="font-size: 13px; font-weight: 600; color: #ffffff;">${escapeHtml(user.username)}</div>
                            <span style="font-size: 9px; padding: 1px 5px; border-radius: 4px; background: ${roleColor.bg}; color: ${roleColor.color}; font-weight: 600;">${escapeHtml(user.role || 'Solicitante')}</span>
                        </div>
                    </div>
                    ${unread > 0 ? `
                        <span style="background: #ff3b30; color: white; font-size: 11px; font-weight: 800; padding: 2px 7px; border-radius: 12px;">${unread}</span>
                    ` : ''}
                </div>
            `;
        });

        listEl.innerHTML = html;
    }

    // --- FORMULARIO PARA CREAR GRUPO ---
    function renderCreateGroupForm() {
        const pane = document.getElementById('sg-chat-create-group-pane');
        if (!pane) return;

        const allUsers = getAllUsers();
        const cur = resolveCurrentUser();
        const myId = cur ? String(cur.id) : '';

        let usersHtml = '';
        allUsers.forEach(u => {
            if (myId && String(u.id) === myId) return;
            const initials = getInitials(u.username);
            usersHtml += `
                <label style="display: flex; align-items: center; justify-content: space-between; padding: 8px 10px; border-radius: 6px; background: rgba(255,255,255,0.03); margin-bottom: 4px; cursor: pointer; user-select: none;">
                    <div style="display: flex; align-items: center; gap: 8px;">
                        <span style="width: 26px; height: 26px; border-radius: 50%; background: #1e3a8a; color: white; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: 700;">${initials}</span>
                        <span style="font-size: 13px; font-weight: 600; color: #ffffff;">${escapeHtml(u.username)}</span>
                    </div>
                    <input type="checkbox" class="sg-group-member-checkbox" value="${u.id}" checked style="width: 18px; height: 18px; cursor: pointer; accent-color: #2563eb;">
                </label>
            `;
        });

        pane.innerHTML = `
            <div style="display: flex; flex-direction: column; height: 100%; padding: 14px; gap: 12px; overflow-y: auto;">
                <div style="background: rgba(251,191,36,0.1); border: 1px solid rgba(251,191,36,0.3); padding: 10px 12px; border-radius: 8px; font-size: 12px; color: #fef08a;">
                    💡 Los grupos permiten coordinar temas específicos (ej. Obras, Electricistas, Compras, etc.) entre varios miembros a la vez.
                </div>
                <div>
                    <label style="display: block; font-size: 12px; font-weight: 700; color: #ffffff; margin-bottom: 6px;">Nombre del Grupo</label>
                    <input type="text" id="sg-new-group-name" placeholder="Ej: Obra Cargill VGG, Mantenimiento..." style="width: 100%; background: rgba(30,41,59,0.85); border: 1.5px solid rgba(56,189,248,0.4); border-radius: 8px; padding: 9px 12px; color: white; font-size: 13px; outline: none;">
                </div>
                <div style="flex: 1; display: flex; flex-direction: column; min-height: 180px;">
                    <label style="display: block; font-size: 12px; font-weight: 700; color: #ffffff; margin-bottom: 6px;">Seleccionar Integrantes</label>
                    <div style="flex: 1; overflow-y: auto; padding-right: 4px; border: 1px solid rgba(255,255,255,0.08); border-radius: 8px; padding: 6px;">
                        ${usersHtml}
                    </div>
                </div>
                <div style="display: flex; gap: 8px; margin-top: auto;">
                    <button type="button" onclick="window.SGChat.showConversationsView()" style="flex: 1; background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.2); color: #cbd5e1; padding: 9px; border-radius: 8px; font-weight: 600; font-size: 13px; cursor: pointer;">
                        Cancelar
                    </button>
                    <button type="button" onclick="window.SGChat.submitCreateGroup()" style="flex: 1.5; background: linear-gradient(135deg, #2563eb, #1d4ed8); border: none; color: white; padding: 9px; border-radius: 8px; font-weight: 700; font-size: 13px; cursor: pointer; box-shadow: 0 4px 12px rgba(37,99,235,0.4);">
                        <i class="fas fa-check"></i> Crear Grupo
                    </button>
                </div>
            </div>
        `;
    }

    function submitCreateGroup() {
        const nameInput = document.getElementById('sg-new-group-name');
        if (!nameInput || !nameInput.value.trim()) {
            if (typeof window.showToast === 'function') window.showToast('Por favor escribe un nombre para el grupo.', 'warning');
            return;
        }

        const memberIds = [];
        document.querySelectorAll('.sg-group-member-checkbox:checked').forEach(cb => {
            memberIds.push(cb.value);
        });

        createGroup(nameInput.value.trim(), memberIds);
    }

    // --- RENDER DE MENSAJES DE LA CONVERSACIÓN ACTIVA ---
    function renderMessages() {
        const bodyEl = document.getElementById('sg-chat-messages-body');
        if (!bodyEl) return;

        const cur = resolveCurrentUser();
        const myId = cur ? String(cur.id) : null;
        if (!myId) {
            bodyEl.innerHTML = '<div style="padding: 20px; text-align: center; color: var(--text-muted);">Iniciá sesión para ver los mensajes.</div>';
            return;
        }

        const type = ChatState.activeConversationType;
        const activeId = String(ChatState.activeConversationId);

        let filtered = [];
        if (type === 'general') {
            filtered = ChatState.messages.filter(m => m.type === 'general' || m.channel === 'general');
        } else if (type === 'group') {
            filtered = ChatState.messages.filter(m => (m.type === 'group' || m.channel === 'group') && String(m.groupId) === activeId);
        } else {
            // Direct message 1 to 1
            filtered = ChatState.messages.filter(m => {
                if (m.type !== 'dm' && m.channel !== 'dm') return false;
                return (String(m.senderId) === myId && String(m.recipientId) === activeId) ||
                       (String(m.senderId) === activeId && String(m.recipientId) === myId);
            });
        }

        if (filtered.length === 0) {
            let emptyLabel = 'No hay mensajes en esta conversación todavía.';
            if (type === 'general') emptyLabel = '¡Escribe el primer mensaje para todo el equipo!';
            else if (type === 'group') emptyLabel = '¡Escribe un mensaje para los miembros de este grupo!';
            else {
                const targetUser = getAllUsers().find(u => String(u.id) === activeId);
                emptyLabel = `¡Escribe un mensaje privado para ${targetUser ? targetUser.username : 'este colega'}!`;
            }

            bodyEl.innerHTML = `
                <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; text-align: center; padding: 24px; color: var(--text-muted);">
                    <div style="font-size: 38px; margin-bottom: 10px; opacity: 0.6;">💬</div>
                    <div style="font-size: 14px; font-weight: 700; color: #ffffff; margin-bottom: 4px;">Comenzar la conversación</div>
                    <div style="font-size: 12px; max-width: 250px;">${emptyLabel}</div>
                </div>
            `;
            return;
        }

        let html = '';
        let lastDateStr = '';

        filtered.forEach(msg => {
            const isMe = String(msg.senderId) === myId;
            const msgDate = new Date(msg.timestamp || Date.now());
            const dateStr = formatDateSeparator(msgDate);
            const timeStr = msgDate.toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' });

            if (dateStr !== lastDateStr) {
                html += `
                    <div style="display: flex; align-items: center; justify-content: center; margin: 12px 0 8px 0;">
                        <span style="font-size: 10px; background: rgba(255,255,255,0.08); color: var(--text-muted); padding: 3px 10px; border-radius: 12px; letter-spacing: 0.3px;">${dateStr}</span>
                    </div>
                `;
                lastDateStr = dateStr;
            }

            const senderInitials = getInitials(msg.senderUsername || 'U');
            const roleColor = getRoleBadgeColor(msg.senderRole);

            if (isMe) {
                html += `
                    <div class="chat-msg-row me" style="display: flex; justify-content: flex-end; margin-bottom: 8px;">
                        <div class="chat-bubble me" style="max-width: 82%; background: linear-gradient(135deg, #2563eb, #1d4ed8); color: white; padding: 8px 12px; border-radius: 14px 14px 2px 14px; box-shadow: 0 2px 8px rgba(37,99,235,0.3); word-break: break-word;">
                            <div style="font-size: 13px; line-height: 1.4;">${escapeHtml(msg.text)}</div>
                            <div style="display: flex; align-items: center; justify-content: flex-end; gap: 4px; margin-top: 3px; font-size: 10px; opacity: 0.85;">
                                <span>${timeStr}</span>
                                <i class="fas fa-check" style="font-size: 9px;"></i>
                            </div>
                        </div>
                    </div>
                `;
            } else {
                html += `
                    <div class="chat-msg-row other" style="display: flex; align-items: flex-start; gap: 8px; margin-bottom: 8px;">
                        <span style="display: flex; align-items: center; justify-content: center; width: 28px; height: 28px; border-radius: 50%; background: #1e3a8a; color: #ffffff; font-weight: 700; font-size: 11px; flex-shrink: 0; border: 1.5px solid #38bdf8;">${senderInitials}</span>
                        <div class="chat-bubble other" style="max-width: 80%; background: rgba(30, 41, 59, 0.88); backdrop-filter: blur(8px); border: 1px solid rgba(56, 189, 248, 0.25); color: #ffffff; padding: 8px 12px; border-radius: 14px 14px 14px 2px; box-shadow: 0 2px 8px rgba(0,0,0,0.25); word-break: break-word;">
                            <div style="display: flex; align-items: center; gap: 6px; margin-bottom: 3px;">
                                <span style="font-size: 11px; font-weight: 700; color: #38bdf8;">${escapeHtml(msg.senderUsername || 'Colega')}</span>
                                <span style="font-size: 9px; padding: 1px 5px; border-radius: 4px; background: ${roleColor.bg}; color: ${roleColor.color}; font-weight: 600;">${escapeHtml(msg.senderRole || '')}</span>
                            </div>
                            <div style="font-size: 13px; line-height: 1.4; color: #f1f5f9;">${escapeHtml(msg.text)}</div>
                            <div style="display: flex; align-items: center; justify-content: flex-end; margin-top: 3px; font-size: 10px; color: var(--text-muted);">
                                <span>${timeStr}</span>
                            </div>
                        </div>
                    </div>
                `;
            }
        });

        bodyEl.innerHTML = html;
        scrollChatToBottom();
    }

    function scrollChatToBottom() {
        const bodyEl = document.getElementById('sg-chat-messages-body');
        if (bodyEl) {
            bodyEl.scrollTop = bodyEl.scrollHeight;
        }
    }

    function renderAllChatViews() {
        renderChatHeader();
        renderConversationsList();
        renderMessages();
    }

    // --- UTILIDADES ---
    function getInitials(name) {
        if (!name) return 'U';
        const parts = name.trim().split(' ');
        if (parts.length >= 2) {
            return (parts[0][0] + parts[1][0]).toUpperCase();
        }
        return name.substring(0, 2).toUpperCase();
    }

    function getRoleBadgeColor(role) {
        const r = String(role || '').toLowerCase();
        if (r.includes('admin')) {
            return { bg: 'rgba(251, 191, 36, 0.2)', color: '#fbbf24' };
        } else if (r.includes('autori')) {
            return { bg: 'rgba(16, 185, 129, 0.2)', color: '#10b981' };
        }
        return { bg: 'rgba(56, 189, 248, 0.2)', color: '#38bdf8' };
    }

    function formatDateSeparator(date) {
        const now = new Date();
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const yesterday = new Date(today);
        yesterday.setDate(yesterday.getDate() - 1);
        const checkDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());

        if (checkDate.getTime() === today.getTime()) return 'Hoy';
        if (checkDate.getTime() === yesterday.getTime()) return 'Ayer';
        return checkDate.toLocaleDateString('es-AR', { day: '2-digit', month: 'short' });
    }

    function escapeHtml(str) {
        if (!str) return '';
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    // --- ENVIAR MENSAJE DESDE INPUT ---
    function triggerSend() {
        const input = document.getElementById('sg-chat-input');
        if (!input) return;
        const text = input.value;
        if (text && text.trim()) {
            sendMessage(text);
            input.value = '';
            input.focus();
        }
    }

    // --- INICIALIZACIÓN DE EVENTOS DOM ---
    function initChatDom() {
        const pillBtn = document.getElementById('online-users-pill');
        const onlineDropdown = document.getElementById('online-users-dropdown');
        if (pillBtn && onlineDropdown) {
            pillBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                const isHidden = onlineDropdown.style.display === 'none' || !onlineDropdown.style.display;
                onlineDropdown.style.display = isHidden ? 'block' : 'none';
                if (isHidden) renderOnlineDropdownList();
            });

            document.addEventListener('click', () => {
                if (onlineDropdown) onlineDropdown.style.display = 'none';
            });
            onlineDropdown.addEventListener('click', (e) => e.stopPropagation());
        }

        const input = document.getElementById('sg-chat-input');
        const sendBtn = document.getElementById('sg-chat-send-btn');
        if (input) {
            input.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    triggerSend();
                } else {
                    notifyTyping();
                }
            });
        }
        if (sendBtn) {
            sendBtn.addEventListener('click', () => triggerSend());
        }

        document.querySelectorAll('.sg-emoji-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                const emoji = btn.getAttribute('data-emoji');
                if (emoji && input) {
                    input.value += emoji;
                    input.focus();
                }
            });
        });
    }

    // --- API PÚBLICA EXPUESTA EN WINDOW ---
    window.SGChat = {
        setUser: setUser,
        toggleChat: toggleChat,
        openChat: openChat,
        closeChat: closeChat,
        openChatWith: openChatWith,
        openGroupChat: openGroupChat,
        openGeneralChat: openGeneralChat,
        showCreateGroupView: showCreateGroupView,
        showConversationsView: showConversationsView,
        submitCreateGroup: submitCreateGroup,
        triggerSend: triggerSend,
        sendMessage: sendMessage,
        refreshPresence: handlePresenceSync,
        init: function() {
            initChatDom();
            resolveCurrentUser();
            if (ChatState.currentUser) {
                setUser(ChatState.currentUser);
            }
            setInterval(() => {
                const u = resolveCurrentUser();
                if (u && !ChatState.currentUser) {
                    setUser(u);
                } else {
                    updateOnlinePillUI();
                }
            }, 1000);
        }
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => window.SGChat.init());
    } else {
        window.SGChat.init();
    }

})();
