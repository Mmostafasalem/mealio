import { Config } from "@remotion/cli/config";

// The bundled headless shell crashes on this Mac; the installed Chrome renders fine.
Config.setBrowserExecutable("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome");
Config.setChromeMode("chrome-for-testing");
