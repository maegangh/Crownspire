/**
 * Crownspire Phase 6 — Direct Message RPC delivery.
 *
 * Private messages are sent through an authenticated Nakama RPC instead of
 * relying on the recipient already being subscribed to a DirectMessage socket
 * channel. The server builds the authoritative DM channel, persists the
 * message, and sends a delivery notification to the recipient.
 *
 * Notification code 5004 is reserved for DM delivery (not Rally 5002 / Help 5001 /
 * Alliance 5003 / Castle 5005).
 */

const DM_NOTIF_CODE = 5004;
const DM_MAX_TEXT_LENGTH = 280;
const DM_SUPPORTED_TYPES: {[key: string]: boolean} = {
  TEXT: true,
  MAP_LOCATION: true,
  RALLY: true,
};

function rpcDmSend(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) {
    throw new Error("Unauthenticated");
  }

  const data = parsePayload(payload);
  const recipientId = String(data.recipient_user_id || "").trim();
  if (recipientId === "" || recipientId === ctx.userId) {
    throw new Error("Invalid DM recipient");
  }

  // Verify the recipient is a real Nakama account before creating a thread.
  const recipients = nk.usersGetId([recipientId]);
  if (!recipients || recipients.length !== 1) {
    throw new Error("Player not found");
  }

  const messageType = String(data.message_type || "TEXT").trim().toUpperCase();
  if (!DM_SUPPORTED_TYPES[messageType]) {
    throw new Error("Unsupported DM message type");
  }

  let text = String(data.text || "").trim();
  if (messageType === "TEXT" && text === "") {
    throw new Error("Message is empty");
  }
  if (text.length > DM_MAX_TEXT_LENGTH) {
    throw new Error("Message exceeds 280 characters");
  }

  const messagePayload = (data.payload && typeof data.payload === "object") ? data.payload : {};
  // Keep structured payloads bounded. This is validation, not authority for gameplay actions.
  const payloadJson = JSON.stringify(messagePayload);
  if (payloadJson.length > 4096) {
    throw new Error("DM payload too large");
  }

  // 1s sender→recipient cooldown (preserves old RtAfter notify window; key cannot
  // collide with rally_*/help_*/dm_notify_* because assertRateLimit keys by action).
  assertRateLimit(nk, ctx.userId, "dm_send_" + recipientId, 1);

  // Server-backed identity: never trust display name or alliance tag supplied by the client.
  const profile = ensureProfile(nk, logger, ctx.userId);
  const senderName = String(profile.display_name || "Player").substring(0, 64);
  const allianceTag = String(profile.alliance_tag || "").substring(0, 8);
  const kingdomId = String(profile.kingdom_id || "");

  // DirectMessage == 2. Nakama canonicalizes the channel for this sender/recipient pair.
  const channelId = nk.channelIdBuild(ctx.userId, recipientId, 2 as any);
  const content: {[key: string]: any} = {
    v: 1,
    message_type: messageType,
    text: text,
    sender_display_name: senderName,
    sender_alliance_tag: allianceTag,
    kingdom_id: kingdomId,
    payload: messagePayload,
    metadata: {
      client_schema: 1,
      tag_authority: "alliance_backend",
      display_name_authority: "alliance_backend",
      delivery_authority: "crownspire_dm_send_rpc",
    },
  };

  const ack = nk.channelMessageSend(channelId, content, ctx.userId, undefined, true);

  const preview = text.substring(0, 120);
  const notifContent = {
    sender_user_id: ctx.userId,
    sender_display_name: senderName,
    preview: preview,
    channel_id: channelId,
    message_id: String((ack as any).messageId || ""),
  };

  try {
    nk.notificationSend(recipientId, "Direct Message", notifContent, DM_NOTIF_CODE, null, true);
  } catch (e) {
    // Message persistence already succeeded. Log notification failure so the recipient
    // can still recover the DM through history on reconnect/open.
    logger.warn("DM delivery notification failed recipient=%s err=%s", recipientId, String(e));
  }

  return JSON.stringify({
    ok: true,
    channel_id: channelId,
    message_id: String((ack as any).messageId || ""),
    create_time: String((ack as any).createTime || ""),
  });
}
