/**
 * Crownspire Phase 6 — Direct Message delivery notifications.
 * When a private DM is sent on an authoritative DirectMessage channel, notify the
 * recipient so their client can join the Nakama channel without the thread open.
 *
 * Security: metadata.dm_recipient_user_id is a hint only. Notifications are sent
 * only when nk.channelIdBuild(ctx.userId, recipientId, DirectMessage) matches the
 * incoming ChannelMessageSend channelId.
 *
 * Rate limit: per-sender/recipient pair via assertRateLimit (1s cooldown). A
 * global per-user notification flood limiter is out of scope for this hook.
 */

const DM_NOTIF_CODE = 5004;
/** nkruntime.ChanType.DirectMessage — Room=1, DirectMessage=2, Group=3 */
const CHANNEL_TYPE_DIRECT = 2;
const PREVIEW_MAX_LEN = 80;
const DISPLAY_NAME_MAX_LEN = 64;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isUuid(value: string): boolean {
  return UUID_RE.test(value);
}

function registerDmHooks(initializer: nkruntime.Initializer): void {
  initializer.registerRtAfter("ChannelMessageSend", afterChannelMessageSend);
}

let afterChannelMessageSend: nkruntime.RtAfterHookFunction<nkruntime.EnvelopeChannelMessageSend> = function (
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  output: nkruntime.EnvelopeChannelMessageSend | null,
  input: nkruntime.EnvelopeChannelMessageSend
): void {
  if (!ctx.userId || !input || !input.channelMessageSend) {
    return;
  }
  const senderId = String(ctx.userId).trim();
  if (!isUuid(senderId)) {
    return;
  }

  const send = input.channelMessageSend;
  const actualChannelId = String(send.channelId || "").trim();
  const contentStr = String(send.content || "");
  if (actualChannelId === "" || contentStr === "") {
    return;
  }

  let content: any = null;
  try {
    content = JSON.parse(contentStr);
  } catch (_e) {
    return;
  }
  if (!content || typeof content !== "object") {
    return;
  }

  const meta = content["metadata"];
  if (!meta || typeof meta !== "object") {
    return;
  }
  const recipientId = String(meta["dm_recipient_user_id"] || "").trim();
  if (!isUuid(recipientId) || recipientId === senderId) {
    return;
  }

  let expectedChannelId: string;
  try {
    expectedChannelId = nk.channelIdBuild(senderId, recipientId, CHANNEL_TYPE_DIRECT);
  } catch (_e) {
    return;
  }
  if (expectedChannelId !== actualChannelId) {
    return;
  }

  try {
    assertRateLimit(nk, senderId, "dm_notify_" + recipientId, 1);
  } catch (_e) {
    return;
  }

  const previewRaw = String(content["text"] || "");
  const preview =
    previewRaw.length > PREVIEW_MAX_LEN
      ? previewRaw.substring(0, PREVIEW_MAX_LEN - 3) + "..."
      : previewRaw;
  const senderName = String(content["sender_display_name"] || "Player").substring(0, DISPLAY_NAME_MAX_LEN);

  let messageId = "";
  const outAny = output as any;
  if (outAny) {
    if (outAny.messageId) {
      messageId = String(outAny.messageId);
    } else if (outAny.channelMessageSend && outAny.channelMessageSend.messageId) {
      messageId = String(outAny.channelMessageSend.messageId);
    }
  }
  if (messageId !== "" && !isUuid(messageId)) {
    messageId = "";
  }

  const notifContent = {
    sender_user_id: senderId,
    sender_display_name: senderName,
    preview: preview,
    channel_id: actualChannelId,
    message_id: messageId,
  };

  try {
    nk.notificationSend(recipientId, "Direct Message", notifContent, DM_NOTIF_CODE, null, true);
  } catch (e) {
    logger.warn("DM delivery notification failed recipient=%s err=%s", recipientId, String(e));
  }
};
