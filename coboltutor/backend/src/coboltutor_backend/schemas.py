"""Request schemas: the JSON contract between the VSCode extension and the backend.

The TypeScript side mirrors these in ``extension/shared/protocol.ts``. If you change
a field here, change it there too.

Pydantic validates every incoming request against these classes. Anything that
doesn't match (a missing field, the wrong type, an over-long string) is rejected
automatically with an HTTP 422 response before our code runs.
"""

from typing import Annotated, Literal

from pydantic import BaseModel, Field, field_validator

# Hard limits that protect the server from huge requests. These are separate from
# (and much larger than) the prompt-size limits in config.py: those trim the
# prompt, these refuse a request outright.
MAX_MESSAGE_CHARS = 20_000
MAX_CODE_CHARS = 200_000
MAX_MESSAGES = 200


class CodeContext(BaseModel):
    """A piece of code from the user's editor, attached to a chat message."""

    # File name for display and for the model's benefit, e.g. "PAYROLL.cbl".
    # Only the base name is sent, not the full path, so nothing about the
    # user's folder layout leaves their machine.
    file_name: str = Field(max_length=500)
    # VSCode's language identifier, e.g. "cobol". Can be anything, because
    # people sometimes open COBOL in files VSCode doesn't recognise.
    language_id: str = Field(default="plaintext", max_length=100)
    # The code itself: either the user's selection or the whole file.
    code: str = Field(max_length=MAX_CODE_CHARS)
    # 1-based, inclusive line numbers of `code` within the file. This lets the
    # model answer "what does line 42 do?" accurately.
    start_line: int = Field(default=1, ge=1)
    end_line: int = Field(default=1, ge=1)
    # True if `code` is a selection, False if it's the whole file.
    is_selection: bool = False


class ChatMessage(BaseModel):
    """One turn in the conversation."""

    # Only "user" and "assistant": the system prompt is always set by the
    # server, so a client can't replace the tutor's instructions.
    role: Literal["user", "assistant"]
    content: str = Field(max_length=MAX_MESSAGE_CHARS)
    # Code attached to this message, if any (only meaningful on user messages).
    code_context: CodeContext | None = None


# One slider answer: 1 = strongly disagree ... 3 = neutral ... 5 = strongly agree.
SliderValue = Annotated[int, Field(ge=1, le=5)]

class StyleProfile(BaseModel):
    """The learner's problem-solving style: five 1-5 sliders (FR-4).

    1 leans to the first style named in each comment, 5 to the second,
    and 3 means neutral (no adaptation for that dimension).
    """
    # Everything defaults to 3, neutral, so we can skip survey for now

    learning_style: SliderValue = 3            # 1 = process-oriented ... 5 = tinkering-oriented
    self_efficacy: SliderValue = 3             # (1 = lower ... 5 = higher)
    risk_attitude: SliderValue = 3             # (1 = risk-averse ... 5 = risk-tolerant)
    motivations: SliderValue = 3               # (1 = task-oriented ... 5 = tech-oriented)
    information_processing: SliderValue = 3    # (1 = comprehensive ... 5 = selective)


class ChatRequest(BaseModel):
    """Body of ``POST /api/chat``: the conversation so far, oldest first."""

    messages: list[ChatMessage] = Field(min_length=1, max_length=MAX_MESSAGES)

    # no profile means the tutor answers in its default (unadapted) style
    profile: StyleProfile | None = None

    @field_validator("messages")
    @classmethod
    def last_message_must_be_from_user(cls, messages: list[ChatMessage]) -> list[ChatMessage]:
        # The model is always replying to the user, so a conversation that ends
        # on an assistant turn means the client is confused about state.
        if messages[-1].role != "user":
            raise ValueError("the last message must have role 'user'")
        return messages
