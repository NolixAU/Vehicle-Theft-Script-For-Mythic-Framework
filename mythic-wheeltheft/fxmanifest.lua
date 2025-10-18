fx_version 'cerulean'
games { 'gta5' }
lua54 'yes'

client_script '@mythic-base/components/cl_error.lua'
client_script '@mythic-pwnzor/client/check.lua'
server_script '@oxmysql/lib/MySQL.lua'

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}