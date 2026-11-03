# ABOUT
This project is a VSCode extension that runs ibm-granite-4.2 off of Ollama that is built to tutor people on IBM COBOL. It should be able to explain code the user has open and answer any questions the user has about code.

# STACK
Frontend:
VSCode Extension API, TypeScript, esbuild
Vue.js
SSE client for streaming from the backend

Backend:
Python + FastAPI (SSE Streaming)
granite-4.2 AI, served by vLLM
RAG: PostgreSQL + granite-embedding
IBM COBOL compiler in a Docker sandbox for compile/syntax checks

Other (data, evaluation, structure):
Knowledge base: 
Open Mainframe Project COBOL course
IBM documentation as the main source
Public sample programs (misc.)
Any approved IBM docs
Environment: Docker Compose
CI: Github Actions


# EXTRA NOTES
Ask any questions you have before writing code or making important decisions, and write very informative comments explaining everything you are doing every step of the way.

