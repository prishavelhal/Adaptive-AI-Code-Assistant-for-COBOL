<!--
  Root component of the chat sidebar: message list, attached-file toggle, and
  input box.

  The extension host owns the conversation. This component only mirrors what
  the host sends (HostToWebview messages) and reports user actions back
  (WebviewToHost messages). See shared/protocol.ts.
-->
<script setup lang="ts">
import { nextTick, onMounted, onUnmounted, ref } from "vue";
import type { HostToWebview, UiMessage } from "../../shared/protocol";
import MessageBubble from "./components/MessageBubble.vue";
import { onHostMessage, postToHost } from "./vscode";

// --- State mirrored from the extension host -----------------------------------
const messages = ref<UiMessage[]>([]);
const streaming = ref(false);
/** Label of the code that would be attached right now, e.g. "HELLO.cbl · whole file". */
const activeLabel = ref<string | null>(null);
const includeActive = ref(true);

// --- Local UI state -------------------------------------------------------------
const draft = ref("");
const scroller = ref<HTMLElement | null>(null);
/** Auto-scroll only while the user is at the bottom; don't yank them back up the page. */
let stickToBottom = true;

function handleHostMessage(msg: HostToWebview): void {
  switch (msg.type) {
    case "state":
      messages.value = msg.messages;
      streaming.value = msg.streaming;
      break;
    case "token": {
      // Append to the last message, the assistant answer being streamed.
      const last = messages.value[messages.value.length - 1];
      if (last && last.role === "assistant") last.content += msg.text;
      break;
    }
    case "activeContext":
      activeLabel.value = msg.label;
      includeActive.value = msg.include;
      return; // no layout change, so no need to scroll
  }
  void scrollToBottomIfStuck();
}

async function scrollToBottomIfStuck(): Promise<void> {
  if (!stickToBottom) return;
  await nextTick(); // wait for Vue to update the DOM first
  const el = scroller.value;
  if (el) el.scrollTop = el.scrollHeight;
}

function onScroll(): void {
  const el = scroller.value;
  if (!el) return;
  // Within 40px of the bottom counts as "at the bottom".
  stickToBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
}

function send(): void {
  const text = draft.value.trim();
  if (!text || streaming.value) return;
  postToHost({ type: "send", text });
  draft.value = "";
  stickToBottom = true;
}

/** Enter sends; Shift+Enter inserts a newline (the usual chat convention). */
function onKeydown(e: KeyboardEvent): void {
  // isComposing: don't send while an IME (e.g. for Japanese input) is mid-composition.
  if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
    e.preventDefault();
    send();
  }
}

function toggleIncludeActive(): void {
  postToHost({ type: "setIncludeActiveFile", include: !includeActive.value });
}

let unsubscribe: (() => void) | undefined;
onMounted(() => {
  unsubscribe = onHostMessage(handleHostMessage);
  // Tell the host we're ready; it replies with the current conversation.
  postToHost({ type: "ready" });
});
onUnmounted(() => unsubscribe?.());
</script>

<template>
  <div class="app">
    <div ref="scroller" class="messages" @scroll="onScroll">
      <div v-if="messages.length === 0" class="welcome">
        <h2>COBOL Tutor</h2>
        <p>Ask anything about IBM COBOL, or about the code you have open.</p>
        <ul>
          <li>Select code, right-click, and choose <b>Explain Selected Code</b> (<kbd>Ctrl+Alt+E</kbd>).</li>
          <li>Right-click anywhere in a file and choose <b>Explain This File</b>.</li>
          <li>Questions you type here include your current file or selection when 📎 is on.</li>
        </ul>
      </div>

      <MessageBubble
        v-for="(m, i) in messages"
        :key="i"
        :message="m"
        :streaming="streaming && i === messages.length - 1"
      />
    </div>

    <div class="composer">
      <button
        class="context-toggle"
        :class="{ off: !includeActive || !activeLabel }"
        :disabled="!activeLabel"
        :title="
          activeLabel
            ? includeActive
              ? 'This code will be attached to your question. Click to stop attaching it.'
              : 'Click to attach this code to your question.'
            : 'Open a file to attach its code to your question.'
        "
        @click="toggleIncludeActive"
      >
        📎 {{ activeLabel ?? "No file open" }}
        <span v-if="activeLabel && !includeActive">(not attached)</span>
      </button>

      <textarea
        v-model="draft"
        rows="3"
        placeholder="Ask about COBOL… (Enter to send, Shift+Enter for a new line)"
        @keydown="onKeydown"
      ></textarea>

      <div class="actions">
        <button v-if="messages.length > 0" class="secondary" @click="postToHost({ type: 'newChat' })">
          New chat
        </button>
        <span class="spacer"></span>
        <button v-if="streaming" class="secondary" @click="postToHost({ type: 'cancel' })">Stop</button>
        <button v-else :disabled="!draft.trim()" @click="send">Send</button>
      </div>
    </div>
  </div>
</template>
