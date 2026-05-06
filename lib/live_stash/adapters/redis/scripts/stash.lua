local key = KEYS[1]
local owner_id = ARGV[1]
local payload = ARGV[2]
local ttl = tonumber(ARGV[3])

local existing_owner = redis.call('HGET', key, 'owner_id')

if existing_owner and existing_owner ~= owner_id then
  return {err = 'Ownership mismatch'}
end

redis.call('HSET', key, 'owner_id', owner_id, 'payload', payload)
redis.call('EXPIRE', key, ttl)

return 'OK'
