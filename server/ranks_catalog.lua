-- ════════════════════════════════════════════════════════════════════════════
-- w_core · server/ranks_catalog.lua
-- Every permission a rank can hold, grouped by what it touches, with a name and a line in plain words
-- (Arabic and English). The ranks page (w_admin) draws its boxes from this list; server/ranks.lua turns
-- the ticked ones into ACE on the rank's principal (wrank.<name>).
--
-- A node is an ACE object, checked by the scripts with IsPlayerAceAllowed / w_lib HasPermissionNode.
-- ACE is hierarchical: 'w_stables.admin' passes 'w_stables.admin.breeding' too. A node starting with
-- 'group.' is not an ACE but a group the rank joins (it inherits everything that group holds).
--
-- ⚠️ 'admin' is the widest node of all: w_lib's HasPermissionNode lets an admin through EVERY script's
--    own node. A specialist rank (horses, shops, the map...) takes its script's node, never 'admin'.
-- Adding a line here is all a new script needs: the page shows it on its next open.
-- ════════════════════════════════════════════════════════════════════════════

local function n(node, ar, en, dar, den, danger)
    return { node = node, label = { ar = ar, en = en }, desc = { ar = dar, en = den }, danger = danger == true }
end

RanksCatalog = {
    {
        id = 'panel', label = { ar = 'لوحة الإدارة والمستويات', en = 'Admin panel and levels' },
        nodes = {
            -- the levels are groups, not bare ACE: joining group.<level> brings the level AND the commands the
            -- scripts register on that group (w_admin's /admin and /staffchat on group.mod, w_inventory's on
            -- group.admin...). group.admin also holds 'command' (every command), group.god holds admin and mod.
            n('group.mod', 'مستوى مشرف (mod)', 'Moderator level (mod)',
                'يفتح لوحة الإدارة F10 و/admin: اللاعبين والطرد والتجميد والمراقبة والخريطة وشات الإدارة.',
                'Opens the F10 panel and /admin: players, kick, freeze, spectate, the map, staff chat.'),
            n('group.admin', 'مستوى إداري (admin)', 'Administrator level (admin)',
                'كل أدوات الإدارة وكل الأوامر، ويعدّي صلاحيات كل السكربتات. لا تعطيه لرتبة متخصصة.',
                'Every admin tool and command, and passes every script\'s own permission. Not for a specialist rank.', true),
            n('group.god', 'مستوى god', 'god level',
                'فوق الإداري: تشغيل السكربتات وإيقافها، حذف الشخصيات وتغيير أرقامها، أوامر الكونسول.',
                'Above admin: start/stop scripts, delete characters, change citizen ids, console commands.', true),
            -- the bare 'command' is the master's alone: it holds add_principal, exec, stop... (server/ranks.lua)
            n('wraithadmin.join', 'الدخول والسيرفر مقفل', 'Join a closed server',
                'يدخل السيرفر حتى لو كان مقفول للصيانة (/closeserver).',
                'Joins the server while it is closed for maintenance (/closeserver).'),
        },
    },
    {
        id = 'players', label = { ar = 'أوامر اللاعبين', en = 'Player commands' },
        nodes = {
            n('command.tp', '/tp — النقل', '/tp — teleport', 'ينتقل لإحداثيات أو للاعب.', 'Teleports to coordinates or to a player.'),
            n('command.tpm', '/tpm — النقل للعلامة', '/tpm — teleport to marker', 'ينتقل للعلامة اللي على الخريطة.', 'Teleports to the map marker.'),
            n('command.givemoney', '/givemoney — إعطاء مال', '/givemoney — give money', 'يعطي لاعب نقد أو بنك.', 'Gives a player cash or bank money.', true),
            n('command.setmoney', '/setmoney — تحديد المال', '/setmoney — set money', 'يحدد مبلغ لاعب.', 'Sets a player\'s balance.', true),
            n('command.setjob', '/setjob — الوظيفة', '/setjob — set job', 'يعيّن وظيفة ورتبة للاعب.', 'Sets a player\'s job and grade.'),
            n('command.setgang', '/setgang — العصابة', '/setgang — set gang', 'يعيّن عصابة للاعب.', 'Sets a player\'s gang.'),
            n('command.givexp', '/givexp — إعطاء خبرة', '/givexp — give XP', 'يزيد خبرة لاعب.', 'Adds XP to a player.'),
            n('command.removexp', '/removexp — سحب خبرة', '/removexp — remove XP', 'ينقص خبرة لاعب.', 'Removes XP from a player.'),
            n('command.givelevel', '/givelevel — رفع المستوى', '/givelevel — give level', 'يرفع مستوى لاعب.', 'Raises a player\'s level.'),
            n('command.removelevel', '/removelevel — إنزال المستوى', '/removelevel — remove level', 'ينزل مستوى لاعب.', 'Lowers a player\'s level.'),
            n('command.revive', '/revive — إنعاش', '/revive — revive', 'ينعش لاعب ميت.', 'Revives a dead player.'),
            n('command.aheal', '/aheal — علاج', '/aheal — heal', 'يعالج لاعب بالكامل.', 'Fully heals a player.'),
            n('command.kill', '/kill — قتل', '/kill — kill', 'يقتل لاعب.', 'Kills a player.'),
            n('command.setpain', '/setpain — الألم', '/setpain — set pain', 'يغيّر ألم لاعب.', 'Changes a player\'s pain.'),
            n('command.horse', '/horse — حصان مؤقت', '/horse — temporary horse', 'يستدعي حصان مؤقت.', 'Spawns a temporary horse.'),
            n('command.wagon', '/wagon — عربة مؤقتة', '/wagon — temporary wagon', 'يستدعي عربة مؤقتة.', 'Spawns a temporary wagon.'),
            n('command.dv', '/dv — حذف عربة', '/dv — delete wagon', 'يحذف العربة القريبة.', 'Deletes the nearby wagon.'),
            n('command.dh', '/dh — حذف حصان', '/dh — delete horse', 'يحذف الحصان القريب.', 'Deletes the nearby horse.'),
            n('command.openserver', '/openserver — فتح السيرفر', '/openserver — open the server', 'يفتح السيرفر للاعبين.', 'Opens the server to players.'),
            n('command.closeserver', '/closeserver — قفل السيرفر', '/closeserver — close the server', 'يقفل السيرفر للصيانة.', 'Closes the server for maintenance.', true),
        },
    },
    {
        id = 'staffcmds', label = { ar = 'أوامر الإدارة', en = 'Staff commands' },
        nodes = {
            n('command.admin', '/admin — فتح اللوحة بالأمر', '/admin — open the panel', 'يفتح لوحة الإدارة بالأمر (يحتاج مستوى mod عشان تنفتح).', 'Opens the admin panel by command (it still needs the mod level).'),
            n('command.staffchat', '/staffchat — شات الإدارة', '/staffchat — staff chat', 'يكتب في شات الإدارة.', 'Writes in the staff chat.'),
            n('command.announce', '/announce — إعلان', '/announce — announcement', 'يرسل إعلان لكل اللاعبين.', 'Sends an announcement to everyone.'),
            n('command.warn', '/warn — تحذير', '/warn — warn', 'يرسل تحذير للاعب.', 'Warns a player.'),
            n('command.noclip', '/noclip — الطيران', '/noclip — noclip', 'يطير ويعدّي الجدران.', 'Flies through walls.'),
            n('command.goto', '/goto — الذهاب للاعب', '/goto — go to player', 'ينتقل عند لاعب.', 'Goes to a player.'),
            n('command.bring', '/bring — إحضار لاعب', '/bring — bring player', 'يجيب لاعب عنده.', 'Brings a player over.'),
            n('command.bringback', '/bringback — إرجاع لاعب', '/bringback — send back', 'يرجّع اللاعب لمكانه.', 'Sends a brought player back.'),
            n('command.reportr', '/reportr — الرد على البلاغات', '/reportr — answer reports', 'يرد على بلاغات اللاعبين.', 'Answers player reports.'),
        },
    },
    {
        id = 'inventory', label = { ar = 'المخزون', en = 'Inventory' },
        nodes = {
            n('command.giveitem', '/giveitem — إعطاء غرض', '/giveitem — give item', 'يعطي لاعب أي غرض.', 'Gives a player any item.', true),
            n('command.additem', '/additem — إضافة غرض', '/additem — add item', 'نفس giveitem.', 'Same as giveitem.', true),
            n('command.removeitem', '/removeitem — سحب غرض', '/removeitem — remove item', 'يسحب غرض من لاعب.', 'Takes an item from a player.'),
            n('command.setitem', '/setitem — تحديد غرض', '/setitem — set item', 'يحدد عدد غرض عند لاعب.', 'Sets an item count on a player.'),
            n('command.viewinv', '/viewinv — مشاهدة الحقيبة', '/viewinv — view bag', 'يشوف حقيبة لاعب.', 'Looks into a player\'s bag.'),
            n('command.takeinv', '/takeinv — أخذ الحقيبة', '/takeinv — take bag', 'ياخذ حقيبة لاعب كاملة.', 'Takes a player\'s whole bag.'),
            n('command.returninv', '/returninv — إرجاع الحقيبة', '/returninv — return bag', 'يرجّع الحقيبة المأخوذة.', 'Returns a taken bag.'),
            n('command.restoreinv', '/restoreinv — استرجاع الحقيبة', '/restoreinv — restore bag', 'نفس returninv.', 'Same as returninv.'),
            n('command.clearinv', '/clearinv — تفريغ الحقيبة', '/clearinv — clear bag', 'يفرّغ حقيبة لاعب.', 'Empties a player\'s bag.', true),
            n('command.saveinv', '/saveinv — حفظ الحقائب', '/saveinv — save bags', 'يحفظ الحقائب الحين.', 'Saves the bags now.'),
        },
    },
    {
        id = 'world', label = { ar = 'الطقس والوقت', en = 'Weather and time' },
        nodes = {
            n('command.weather', '/weather — الطقس', '/weather — weather', 'يغيّر الطقس.', 'Changes the weather.'),
            n('command.time', '/time — الوقت', '/time — time', 'يغيّر الساعة.', 'Changes the clock.'),
            n('command.morning', '/morning — الصباح', '/morning — morning', 'يخلي الوقت صباح.', 'Sets the time to morning.'),
            n('command.noon', '/noon — الظهر', '/noon — noon', 'يخلي الوقت ظهر.', 'Sets the time to noon.'),
            n('command.evening', '/evening — المساء', '/evening — evening', 'يخلي الوقت مساء.', 'Sets the time to evening.'),
            n('command.night', '/night — الليل', '/night — night', 'يخلي الوقت ليل.', 'Sets the time to night.'),
            n('command.freezetime', '/freezetime — تجميد الوقت', '/freezetime — freeze time', 'يوقّف الساعة.', 'Stops the clock.'),
            n('command.freezeweather', '/freezeweather — تجميد الطقس', '/freezeweather — freeze weather', 'يثبّت الطقس.', 'Locks the weather.'),
            n('command.blackout', '/blackout — انقطاع الكهرباء', '/blackout — blackout', 'يطفي الأنوار.', 'Turns the lights off.'),
        },
    },
    {
        id = 'stables', label = { ar = 'الإسطبلات والخيل', en = 'Stables and horses' },
        nodes = {
            n('w_stables.admin', 'إدارة الإسطبلات كاملة', 'Full stables admin', 'كل لوحة /stables بكل أقسامها.', 'The whole /stables board, every area.'),
            n('w_stables.admin.stables', 'الأسواق ومحطات التلقيح', 'Markets and studs', 'إدارة الأسواق ومحطات التلقيح وأعمالها.', 'Markets, studs and their business.'),
            n('w_stables.admin.catalogue', 'الكتالوج', 'Catalogue', 'أنواع العربات وأرقامها.', 'Wagon types and their numbers.'),
            n('w_stables.admin.balancing', 'الموازنة', 'Balancing', 'إعدادات الإسطبلات.', 'Stables settings.'),
            n('w_stables.admin.records', 'السجلات', 'Records', 'قراءة كل السجلات.', 'Reads every registry.'),
            n('w_stables.admin.ownership', 'الملكية', 'Ownership', 'إعطاء ونقل وعلاج وحذف الخيل والعربات.', 'Give, move, heal, delete horses and wagons.', true),
            n('w_stables.admin.breeding', 'التربية', 'Breeding', 'الحمل وفحوص الجينات وتعديلها.', 'Pregnancies and gene tests and edits.'),
            n('w_stables.admin.migration', 'الترحيل', 'Migration', 'سجل ترحيل الخيل القديمة.', 'The old horses\' migration record.'),
            n('w_pets.admin', 'الحيوانات الأليفة', 'Pets', 'إدارة الحيوانات الأليفة ومتاجرها.', 'Pets and their shops.'),
        },
    },
    {
        id = 'economy', label = { ar = 'الاقتصاد والمتاجر', en = 'Economy and shops' },
        nodes = {
            n('w_store.admin', 'المتاجر', 'Stores', 'إدارة المتاجر والبضاعة والأسعار.', 'Stores, stock and prices.'),
            n('w_butcher.admin', 'الجزّار', 'Butcher', 'إدارة الجزّارين ومستويات اللاعبين عندهم.', 'Butchers and the players\' levels with them.'),
            n('w_level.admin', 'المستويات والخبرة', 'Levels and XP', 'إعطاء وسحب الخبرة والمستويات.', 'Gives and removes XP and levels.'),
        },
    },
    {
        id = 'jobs', label = { ar = 'الوظائف والمهمات', en = 'Jobs and missions' },
        nodes = {
            n('w_jobs.view', 'الوظائف: مشاهدة', 'Jobs: view', 'يفتح /jobs ويقرأ كل الوظائف بدون تعديل.', 'Opens /jobs and reads every job, no changes.'),
            n('w_jobs.edit', 'الوظائف: تعديل', 'Jobs: edit', 'يسوي ويعدّل المسودات ويجرّبها.', 'Creates, edits and tests drafts.'),
            n('w_jobs.publish', 'الوظائف: نشر', 'Jobs: publish', 'ينشر ويوقف ويرجّع ويحذف الوظائف.', 'Publishes, disables, rolls back and deletes jobs.'),
            n('w_missions.admin', 'المهمات', 'Missions', 'إدارة المهمات ولوحتها.', 'Missions and their board.'),
        },
    },
    {
        id = 'map', label = { ar = 'الخريطة', en = 'Map' },
        nodes = {
            n('w_map.editor', 'محرر الخريطة', 'Map editor', 'يعدّل العلامات والأسماء على الخريطة.', 'Edits the blips and labels on the map.'),
            n('w_map.teleport', 'النقل من الخريطة', 'Map teleport', 'ينتقل لنقطة على الخريطة (/tpwp).', 'Teleports to a map point (/tpwp).'),
            n('w_map.roads', 'استخراج الطرق والمناطق', 'Roads and zones extraction', 'أوامر /maproads و/mapzones و/maplabels.', 'The /maproads, /mapzones, /maplabels commands.'),
        },
    },
    {
        id = 'places', label = { ar = 'الأماكن والأبواب', en = 'Places and doors' },
        nodes = {
            n('w_doorlock.admin', 'الأقفال', 'Door locks', 'يضيف ويعدّل الأبواب ومفاتيحها (/doorlock).', 'Adds and edits doors and their keys (/doorlock).'),
            n('w_doorlock.door', 'فتح كل الأبواب', 'Open every door', 'يفتح أي باب مقفل بدون مفتاح.', 'Opens any locked door without a key.', true),
            n('wraith_cinema.admin', 'السينما: كاملة', 'Cinema: full', 'كل صلاحيات السينما.', 'Every cinema permission.'),
            n('wraith_cinema.control', 'السينما: التحكم', 'Cinema: control', 'تشغيل وإيقاف العروض.', 'Plays and stops shows.'),
            n('wraith_cinema.schedule', 'السينما: الجدول', 'Cinema: schedule', 'يرتّب جدول العروض.', 'Arranges the schedule.'),
            n('wraith_cinema.broadcast', 'السينما: الإعلانات', 'Cinema: announcements', 'يرسل إعلانات السينما.', 'Sends cinema announcements.'),
            n('wraith_cinema.calibrate', 'السينما: المعايرة', 'Cinema: calibration', 'يضبط الشاشات.', 'Calibrates the screens.'),
            n('wraith_cinema.logs', 'السينما: السجل', 'Cinema: logs', 'يقرأ سجل السينما.', 'Reads the cinema log.'),
            n('w_baloot.admin', 'البلوت', 'Baloot', 'يضيف ويحذف طاولات البلوت (/baloot).', 'Adds and removes Baloot tables (/baloot).'),
        },
    },
    {
        id = 'system', label = { ar = 'النظام والسجلات', en = 'System and logs' },
        nodes = {
            n('w_logs.view', 'السجلات: مشاهدة', 'Logs: view', 'يفتح لوحة السجلات (/logs).', 'Opens the logs panel (/logs).'),
            n('w_logs.discord', 'السجلات: ديسكورد', 'Logs: Discord', 'يعدّل إرسال السجلات لديسكورد.', 'Changes where logs go on Discord.'),
            n('w_hud.admin', 'إعدادات الـHUD', 'HUD settings', 'يعدّل إعدادات الجوع والعطش والـHUD.', 'Changes hunger, thirst and HUD settings.'),
            n('w_pausemenu.console', 'كونسول F8', 'F8 console', 'يقدر يفتح كونسول F8 بدون طرد.', 'May open the F8 console without a kick.'),
            n('w_creators.admin', 'الشخصيات والملابس', 'Characters and clothes', 'أدوات إدارة الشخصيات في w_creators.', 'w_creators\' character admin tools.'),
            n('w_creators.dev', 'أدوات مطوّر الشخصيات', 'Character dev tools', 'أدوات المطورين في w_creators.', 'w_creators\' developer tools.', true),
        },
    },
}

--- Every node of the catalogue, flat (the master rank holds them all)
function RanksCatalogNodes()
    local out = {}
    for _, group in ipairs(RanksCatalog) do
        for _, item in ipairs(group.nodes) do out[#out + 1] = item.node end
    end
    return out
end

-- The roots the master rank also holds, so a node a script adds later passes without editing this file
RanksMasterRoots = {
    'command', 'god', 'admin', 'mod', 'wraithadmin', 'w_stables', 'w_pets', 'w_store', 'w_butcher', 'w_level',
    'w_jobs', 'w_missions', 'w_map', 'w_doorlock', 'wraith_cinema', 'w_baloot', 'w_logs', 'w_hud', 'w_pausemenu',
    'w_creators', 'w_guarma', 'w_crafting', 'w_tribes', 'w_inventory', 'w_admin', 'w_core', 'w_lib',
}

-- ════════════════════════════════════════════════════════════════════════════
-- The WEBSITE's permissions (wraith7.com, through w_connector). One rank system for both: a rank
-- holds these beside its in-game nodes, and the website reads them through w_connector
-- (adminpanel:getRolesAndPermissions). They are no ACE (web = true: server/ranks.lua does not apply
-- them in game) -- w_connector checks them itself, by exact name. The names are w_connector's
-- PERMISSION_NODES (server/sv_schema.lua): the website's contract, append-only.
-- ════════════════════════════════════════════════════════════════════════════

local function w(node, ar, en) return n(node, ar, en, 'من الموقع: ' .. ar, 'On the website: ' .. en) end

local WEB_GROUPS = {
    { id = 'web_general', label = { ar = 'الموقع: عام', en = 'Website: general' }, nodes = {
        w('access_admin_panel', 'دخول لوحة الموقع', 'Open the website panel'),
        w('access_logs', 'السجلات', 'Logs'),
    } },
    { id = 'web_players', label = { ar = 'الموقع: اللاعبين', en = 'Website: players' }, nodes = {
        w('players_page', 'صفحة اللاعبين والحقائب', 'Players page and bags'),
        w('player.kick', 'طرد', 'Kick'), w('player.warn', 'تحذير', 'Warn'), w('player.removewarn', 'حذف تحذير', 'Remove a warning'),
        w('player.heal', 'علاج', 'Heal'), w('player.revive', 'إنعاش', 'Revive'), w('player.respawn', 'إحياء', 'Respawn'),
        w('player.kill', 'قتل', 'Kill'), w('player.freeze', 'تجميد', 'Freeze'), w('player.spectate', 'مراقبة (بث مباشر)', 'Spectate (live view)'),
        w('player.message', 'رسالة خاصة', 'Private message'), w('player.troll', 'المقالب', 'Troll effects'),
        w('player.removeweapon', 'سحب السلاح', 'Remove weapon'),
        w('player.teleport.to_player', 'الذهاب للاعب', 'Go to player'), w('player.teleport.bring', 'إحضار لاعب', 'Bring player'),
        w('player.inventory.remove_items', 'سحب أسلحة وأغراض', 'Remove weapons and items'),
        w('player.inventory.clear', 'تفريغ الحقيبة', 'Clear the bag'),
        w('add.item.to_player', 'إعطاء غرض', 'Give an item'), w('remove.item.from_player', 'سحب غرض', 'Take an item'),
    } },
    { id = 'web_bans', label = { ar = 'الموقع: الحظر', en = 'Website: bans' }, nodes = {
        w('show_banned_players', 'قائمة المحظورين', 'Banned players list'), w('ban_history', 'سجل الحظر', 'Ban history'),
        w('edit_ban', 'تعديل حظر', 'Edit a ban'), w('unban_player', 'رفع الحظر', 'Unban'),
        w('player.ban.temporary', 'حظر مؤقت', 'Temporary ban'), w('player.ban.permanent', 'حظر دائم', 'Permanent ban'),
        w('get_player_warnings', 'تحذيرات اللاعب', 'Player warnings'),
    } },
    { id = 'web_character', label = { ar = 'الموقع: الشخصيات', en = 'Website: characters' }, nodes = {
        w('set.nickname', 'اللقب', 'Nickname'), w('set.firstname', 'الاسم الأول', 'First name'),
        w('set.lastname', 'اسم العائلة', 'Last name'), w('set.age', 'العمر', 'Age'),
        w('set.chardescription', 'الوصف', 'Description'), w('set.jobwithgrade', 'الوظيفة والرتبة', 'Job with grade'),
        w('set.joblabel', 'اسم الوظيفة', 'Job label'), w('set.jobgrade', 'رتبة الوظيفة', 'Job grade'),
        w('currency.addorremove', 'إضافة وسحب المال', 'Add or remove money'),
        w('add.xp', 'إضافة خبرة', 'Add XP'), w('remove.xp', 'سحب خبرة', 'Remove XP'),
    } },
    { id = 'web_whitelist', label = { ar = 'الموقع: القائمة البيضاء', en = 'Website: whitelist' }, nodes = {
        w('whitelist.view', 'مشاهدة', 'View'), w('whitelist.add', 'إضافة', 'Add'), w('whitelist.edit', 'تعديل', 'Edit'),
        w('whitelist.remove', 'حذف', 'Remove'), w('whitelist.suspend', 'إيقاف', 'Suspend'),
        w('whitelist.activate', 'تفعيل', 'Activate'), w('whitelist.approve', 'قبول', 'Approve'),
    } },
    { id = 'web_staff', label = { ar = 'الموقع: الإدارة', en = 'Website: staff' }, nodes = {
        w('admins.view', 'قائمة الإدارة والرتب', 'Staff and ranks list'),
        w('admin.action', 'طرد إداري', 'Kick a staff member'),
        w('change.admin.role', 'تغيير رتبة إداري (للماستر)', 'Change a staff rank (master)'),
        w('manage_permissions', 'إدارة الرتب (للماستر)', 'Manage ranks (master)'),
        w('adminchat.view', 'قراءة شات الإدارة', 'Read the staff chat'), w('adminchat.send', 'الكتابة في شات الإدارة', 'Write in the staff chat'),
        w('ignore_while_kicking_allplayers', 'ما ينطرد مع طرد الكل', 'Stays on a kick-all'),
    } },
    { id = 'web_reports', label = { ar = 'الموقع: البلاغات', en = 'Website: reports' }, nodes = {
        w('admin.reports.view', 'مشاهدة', 'View'), w('admin.reports.claim', 'استلام', 'Claim'),
        w('admin.reports.resolve', 'إنهاء', 'Resolve'), w('admin.reports.reopen', 'إعادة فتح', 'Reopen'),
        w('admin.reports.message', 'الرد', 'Reply'),
    } },
    { id = 'web_server', label = { ar = 'الموقع: السيرفر', en = 'Website: server' }, nodes = {
        w('view.statistics', 'الإحصائيات', 'Statistics'), w('view.livemap', 'الخريطة المباشرة', 'Live map'),
        w('livemap.action', 'أوامر الخريطة', 'Live map actions'), w('resource.action', 'تشغيل وإيقاف السكربتات', 'Start and stop scripts'),
        w('refresh_resources', 'تحديث السكربتات', 'Refresh scripts'), w('schedule_restart', 'جدولة إعادة التشغيل', 'Schedule a restart'),
        w('send_announcement', 'إعلان', 'Announcement'), w('close_server_for_players', 'قفل السيرفر', 'Close the server'),
        w('admin.kickall', 'طرد الكل', 'Kick everyone'),
        w('server.time.control', 'الوقت', 'Time'), w('server.weather.control', 'الطقس', 'Weather'),
        w('server.timescale.control', 'سرعة الوقت', 'Time scale'), w('server.wind.control', 'الرياح', 'Wind'),
        w('server.syncdelay.control', 'تأخير المزامنة', 'Sync delay'),
    } },
    { id = 'web_queue', label = { ar = 'الموقع: الدخول والطابور', en = 'Website: entry and queue' }, nodes = {
        w('queue.view', 'مشاهدة الطابور والأولويات', 'View the queue and priorities'),
        w('queue.manage', 'إدارة الدخول (الطابور، الأولوية، القفل، القائمة البيضاء)', 'Manage entry (queue, priority, closing, whitelist)'),
    } },
    { id = 'web_site', label = { ar = 'الموقع: صفحات الموقع', en = 'Website: site pages' }, nodes = {
        w('site.manage', 'إدارة الموقع', 'Manage the site'), w('site.rules', 'القوانين', 'Rules'),
        w('site.applications', 'طلبات التقديم', 'Applications'), w('site.bans', 'حظر الموقع', 'Site bans'),
        w('site.store', 'المتجر', 'Store'), w('site.shop', 'المحل', 'Shop'), w('site.login', 'تسجيل الدخول', 'Login settings'),
    } },
}

RanksWebNodes = {}
for _, group in ipairs(WEB_GROUPS) do
    group.web = true
    for _, item in ipairs(group.nodes) do
        item.web = true
        RanksWebNodes[item.node] = true
    end
    RanksCatalog[#RanksCatalog + 1] = group
end
