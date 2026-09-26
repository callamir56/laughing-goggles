lib.addCommand(Config.Commands.create, {
    help = 'Create and manage gangs'
}, function(source)
    if not HasAdmin(source) then
        return TriggerClientEvent('esx:showNotification', source, 'No permission')
    end
    TriggerClientEvent('esx_gangs:openPanel', source, GetGangs(), nil)
end)

lib.addCommand(Config.Commands.setgang, {
    help = 'Set player gang',
    params = {
        { name = 'id', type = 'playerId', help = 'Player id' },
        { name = 'gang', type = 'string', help = 'Gang name or none' },
        { name = 'rank', type = 'number', help = 'Rank grade' }
    }
}, function(source, args)
    local ok, reason = SetPlayerGang(source, args.id, args.gang, args.rank)
    if not ok then
        local msg = ({
            no_perm = 'No permission',
            no_player = 'Player is not online',
            no_gang = 'Gang not found',
            no_rank = 'Invalid rank'
        })[reason] or 'Error'
        return TriggerClientEvent('esx:showNotification', source, msg)
    end
    if reason == 'removed' then
        TriggerClientEvent('esx:showNotification', source, 'Removed from gang')
        TriggerClientEvent('esx:showNotification', args.id, 'You were removed from the gang')
    else
        TriggerClientEvent('esx:showNotification', source, 'Added to gang')
        TriggerClientEvent('esx:showNotification', args.id, 'You joined the gang')
    end
end)

lib.addCommand(Config.Commands.addcar, {
    help = 'Add current vehicle to gang garage',
    params = {
        { name = 'gang', type = 'string', help = 'Exact gang name' }
    }
}, function(source, args)
    if not HasAdmin(source) then
        return TriggerClientEvent('esx:showNotification', source, 'No permission')
    end
    TriggerClientEvent('esx_gangs:tryAddCar', source, args.gang)
end)
