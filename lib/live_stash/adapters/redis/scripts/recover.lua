local key = KEYS[1]
local new_owner_id = ARGV[1]
local ttl = tonumber(ARGV[2])

local payload = redis.call('HGET', key, 'payload')
if not payload then
  return nil
end

redis.call('HSET', key, 'owner_id', new_owner_id)
redis.call('EXPIRE', key, ttl)

return payload
