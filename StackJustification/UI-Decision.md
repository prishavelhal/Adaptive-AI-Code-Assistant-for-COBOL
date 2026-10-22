# UI Direction and Framework
## Frontend Team Report

### UI Choice 
**Interface Decision:** VSCode Extension

A chat panel on the right side of the screen similar to VSCode Copilot chat, next to the COBOL file the user is working on. 
### Inspiration
1. VSCode Co-pilot chatbot
2. VSCode-chat (arjunattam): Chat opens on the right with a nice gui
3. VSCode-chat (NathanCooper): a chatbot that reads off of the program file selected.

### 3. React vs Vue 
| | React | Vue |
|---|---|---|
| Learning | Fit for a chat panel UI, Should in theory be easy to make | One of the inspired projects utilizes it, lots of inspiration avaliable |
| Team familiarity | Both UI Devlopers worked with it | A small amount of experience|
| Learning curve | Requires more conventions to agree on (state, routing, structure) | Gentler curve, fewer moving parts |
| Setup effort for quiz | Easy addition | Easy addition |


**Decision:** Vue has been chosen as the framework as React requires fewer decisions to coordinate and less chances of discoordinated decisions.

**Reasoning:** Even though React has stronger team familiarity, it requires more conventions to agree on, which will raise a risk of inconsistent decisions across teams working in parallel. Vue's framework mean less perfectly coordinated decisions especially with a group as big as ours. Vue is also a framework with a lower learning curve, meaning the lost of familiarity is not a big loss.
