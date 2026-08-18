extends RefCounted
class_name AccountEmailAuth

## Phase 4 — shared email form validation + safe error mapping.
## Never stores passwords. Never logs passwords or tokens.

const MIN_PASSWORD_LEN := 8

const ERR_INVALID_EMAIL := "INVALID_EMAIL"
const ERR_PASSWORD_TOO_SHORT := "PASSWORD_TOO_SHORT"
const ERR_PASSWORD_MISMATCH := "PASSWORD_MISMATCH"
const ERR_EMAIL_IN_USE := "EMAIL_ALREADY_IN_USE"
const ERR_INVALID_CREDENTIALS := "INVALID_CREDENTIALS"
const ERR_NETWORK := "NETWORK_UNAVAILABLE"
const ERR_RATE_LIMITED := "RATE_LIMITED"
const ERR_ACCOUNT_MISMATCH := "ACCOUNT_MISMATCH"
const ERR_CLOUD_CONFLICT := "CLOUD_CONFLICT"
const ERR_NOT_AUTH := "NOT_AUTHENTICATED"
const ERR_USER_CHANGED := "USER_ID_CHANGED"
const ERR_AUTH_FAILED := "AUTH_FAILED"
const ERR_GATE_REQUIRED := "LOGIN_GATE_REQUIRED"
const ERR_GUEST_SWITCH_BLOCKED := "GUEST_SWITCH_BLOCKED"
const ERR_PROVIDER_UNAVAILABLE := "PROVIDER_UNAVAILABLE"
const ERR_MISSING_TOKEN := "MISSING_IDENTITY_TOKEN"
const ERR_IDENTITY_IN_USE := "IDENTITY_ALREADY_IN_USE"


static func validate_email(email: String) -> Dictionary:
	var e: String = email.strip_edges().to_lower()
	if e.is_empty() or e.find("@") < 1:
		return {"ok": false, "error": ERR_INVALID_EMAIL, "message": "Enter a valid email address."}
	var at: int = e.find("@")
	var domain: String = e.substr(at + 1)
	if domain.find(".") < 1 or e.ends_with(".") or e.begins_with("."):
		return {"ok": false, "error": ERR_INVALID_EMAIL, "message": "Enter a valid email address."}
	# Reject whitespace / obvious garbage.
	if e.find(" ") >= 0:
		return {"ok": false, "error": ERR_INVALID_EMAIL, "message": "Enter a valid email address."}
	return {"ok": true, "email": e}


static func validate_password(password: String) -> Dictionary:
	if password.length() < MIN_PASSWORD_LEN:
		return {
			"ok": false,
			"error": ERR_PASSWORD_TOO_SHORT,
			"message": "Password must be at least %d characters." % MIN_PASSWORD_LEN,
		}
	return {"ok": true}


static func validate_secure_form(email: String, password: String, confirm: String) -> Dictionary:
	var ev: Dictionary = validate_email(email)
	if not bool(ev.get("ok", false)):
		return ev
	var pv: Dictionary = validate_password(password)
	if not bool(pv.get("ok", false)):
		return pv
	if password != confirm:
		return {"ok": false, "error": ERR_PASSWORD_MISMATCH, "message": "Passwords do not match."}
	return {"ok": true, "email": str(ev.get("email", ""))}


static func validate_login_form(email: String, password: String) -> Dictionary:
	var ev: Dictionary = validate_email(email)
	if not bool(ev.get("ok", false)):
		return ev
	var pv: Dictionary = validate_password(password)
	if not bool(pv.get("ok", false)):
		return pv
	return {"ok": true, "email": str(ev.get("email", ""))}


static func mask_email(email: String) -> String:
	var e: String = email.strip_edges().to_lower()
	var at: int = e.find("@")
	if at < 1:
		return ""
	var local: String = e.substr(0, at)
	var domain: String = e.substr(at + 1)
	var head: String = local.substr(0, 1)
	return "%s***@%s" % [head, domain]


static func user_message_for_code(code: String) -> String:
	match code:
		ERR_INVALID_EMAIL:
			return "Enter a valid email address."
		ERR_PASSWORD_TOO_SHORT:
			return "Password must be at least %d characters." % MIN_PASSWORD_LEN
		ERR_PASSWORD_MISMATCH:
			return "Passwords do not match."
		ERR_EMAIL_IN_USE:
			return "That email is already linked to another Crownspire account."
		ERR_INVALID_CREDENTIALS:
			return "Incorrect email or password."
		ERR_NETWORK:
			return "Network unavailable. Check your connection and try again."
		ERR_RATE_LIMITED:
			return "Too many attempts. Please wait and try again."
		ERR_ACCOUNT_MISMATCH:
			return "This device has progress for a different account. Switching will leave the other progress on this device."
		ERR_CLOUD_CONFLICT:
			return "Cloud save conflict needs attention before continuing."
		ERR_NOT_AUTH:
			return "You must be signed in before securing this account."
		ERR_USER_CHANGED:
			return "Account identity changed unexpectedly. Progress was not merged."
		ERR_GATE_REQUIRED:
			return "Please log in to continue with your secured Crownspire account."
		ERR_GUEST_SWITCH_BLOCKED:
			return "This Guest Account has purchases or currency that would be left behind. Secure it with a Mythic Crown Studios Account before logging into a different account."
		ERR_PROVIDER_UNAVAILABLE:
			return "This sign-in method is not available in this build."
		ERR_MISSING_TOKEN:
			return "Account link failed."
		ERR_IDENTITY_IN_USE:
			return "That Google account is already linked to another Crownspire account."
		_:
			return "Authentication failed. Please try again."


static func map_nakama_exception(message: String) -> Dictionary:
	var msg: String = message.strip_edges()
	var lower: String = msg.to_lower()
	if lower.find("rate") >= 0 or lower.find("limit") >= 0 or lower.find("429") >= 0:
		return {"error": ERR_RATE_LIMITED, "message": user_message_for_code(ERR_RATE_LIMITED)}
	if (
		lower.find("already") >= 0
		or lower.find("in use") >= 0
		or lower.find("exists") >= 0
		or lower.find("duplicate") >= 0
	):
		return {"error": ERR_EMAIL_IN_USE, "message": user_message_for_code(ERR_EMAIL_IN_USE)}
	if (
		lower.find("invalid") >= 0
		or lower.find("credential") >= 0
		or lower.find("password") >= 0
		or lower.find("not found") >= 0
		or lower.find("unauthorized") >= 0
		or lower.find("401") >= 0
	):
		return {"error": ERR_INVALID_CREDENTIALS, "message": user_message_for_code(ERR_INVALID_CREDENTIALS)}
	if (
		lower.find("network") >= 0
		or lower.find("timeout") >= 0
		or lower.find("unreachable") >= 0
		or lower.find("connection") >= 0
	):
		return {"error": ERR_NETWORK, "message": user_message_for_code(ERR_NETWORK)}
	# Do not surface raw backend text.
	return {"error": ERR_AUTH_FAILED, "message": user_message_for_code(ERR_AUTH_FAILED)}


static func map_google_nakama_exception(message: String) -> Dictionary:
	var mapped: Dictionary = map_nakama_exception(message)
	if str(mapped.get("error", "")) == ERR_EMAIL_IN_USE:
		return {
			"error": ERR_IDENTITY_IN_USE,
			"message": user_message_for_code(ERR_IDENTITY_IN_USE),
		}
	return mapped
