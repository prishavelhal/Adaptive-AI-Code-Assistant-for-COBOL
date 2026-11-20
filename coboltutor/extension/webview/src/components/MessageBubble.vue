<!--
  One chat message. User messages are shown as plain text (exactly what they
  typed); assistant messages are rendered from Markdown.

  In agent mode (setting `coboltutor.useAgents`) an assistant message can also
  carry the pipeline step that's running (`stage`) and, once the answer is
  finished, the Critic's findings (`verification`), shown under the answer.
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

/** Friendly text for each pipeline step (names come from the backend orchestrator). */
const STAGE_LABELS: Record<string, string> = {
  analyze: "Analyzing the code…",
  explain: "Writing the explanation…",
  verify: "Checking the answer…",
};
const stageLabel = computed(() =>
  props.message.stage ? (STAGE_LABELS[props.message.stage] ?? "Working…") : undefined,
);

const issues = computed(() => props.message.verification?.issues ?? []);
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
      <!-- Before the first token: the current step in agent mode, else "Thinking…". -->
      <div v-else-if="streaming" class="body thinking">{{ stageLabel ?? "Thinking…" }}</div>
      <!-- After the answer has streamed, the Critic runs: say so instead of going quiet. -->
      <div v-if="streaming && message.content && message.stage === 'verify'" class="note">
        {{ stageLabel }}
      </div>
    </template>

    <!-- The Critic's findings. Plain text interpolation ({{ }}), never v-html,
         because the messages can quote text from the model's answer. -->
    <div v-if="issues.length" class="verification warn">
      <div class="verification-title">
        ⚠ Possible {{ issues.length === 1 ? "problem" : "problems" }} in this answer
      </div>
      <ul>
        <li v-for="(issue, i) in issues" :key="i">
          {{ issue.message }}
          <span v-if="issue.source === 'review'" class="issue-source">(model review)</span>
        </li>
      </ul>
    </div>
    <div v-else-if="message.verification" class="verification ok">
      ✓ Checked against the code{{ message.verification.reviewed_by_model ? " and reviewed" : "" }}:
      no problems found.
    </div>

    <div v-if="message.stopped" class="note">Stopped.</div>
    <div v-if="message.error" class="error">⚠ {{ message.error }}</div>
  </div>
</template>
