class_name ReleaseVerify

const PUBLIC_KEY := "res://assets/keys/public.pub"


static func signed(sums: PackedByteArray, signature: PackedByteArray) -> bool:
	var key := CryptoKey.new()
	if key.load(PUBLIC_KEY, true) != OK:
		return false
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(sums)
	return Crypto.new().verify(HashingContext.HASH_SHA256, ctx.finish(), signature, key)


static func expected_hash(sums: String, asset_name: String) -> String:
	for line in sums.split("\n", false):
		var parts := line.split(" ", false)
		if parts.size() >= 2 and parts[parts.size() - 1].get_file() == asset_name:
			return parts[0]
	return ""
