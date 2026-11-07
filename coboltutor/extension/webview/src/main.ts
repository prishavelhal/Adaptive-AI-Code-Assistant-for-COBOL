// Webview entry point: mounts the Vue app into the #app div of the webview HTML.
import { createApp } from "vue";
import App from "./App.vue";
import "./style.css";

createApp(App).mount("#app");
