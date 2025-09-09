ROLE_SLASHER = 1
ROLE_SURVIVOR = 2

function GetRoleName(role)
    if role == ROLE_SLASHER then
        return "Slasher"
    elseif role == ROLE_SURVIVOR then
        return "Survivor"
    end
    return "Unknown"
end
