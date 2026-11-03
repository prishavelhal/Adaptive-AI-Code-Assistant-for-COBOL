<!--
  One chat message. User messages are shown as plain text (exactly what they
  typed); assistant messages are rendered from Markdown.
-->
<script setup lang="ts">
import { computed } from "vue";
import type { UiMessage } from "../../../shared/protocol";
import { renderMarkdown } from "../markdown";

const props = defineProps<{
  message: UiMessage;
  /** true for the assistant message currently being generated. */
  streaming: boolean;
}>();

// Re-renders whenever `content` changes, i.e. on every streamed token. That's
// cheap at chat-answer sizes, and the answer always shows correctly formatted
// Markdown, even partway through.
const html = computed(() => renderMarkdown(props.message.content));
</script>

<template>
  <div class="message" :class="message.role">
    <div class="role">{{ message.role === "user" ? "You" : "CobolTutor" }}</div>

    <div v-if="message.contextLabel" class="context-chip" title="Code attached to this message">
      📎 {{ message.contextLabel }}
    </div>

    <div v-if="message.role === 'user'" class="body user-text">{{ message.content }}</div>
    <template v-else>
      <!-- v-html is safe here: renderMarkdown sanitises its output. -->
      <div v-if="message.content" class="body markdown" v-html="html"></div>
      <div v-else-if="streaming" class="body thinking">Thinking…</div>
    </template>

    <div v-if="message.stopped" class="note">Stopped.</div>
    <div v-if="message.error" class="error">⚠ {{ message.error }}</div>
  </div>
</template>
