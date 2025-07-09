// Use https://finicky-kickstart.now.sh to generate basic configuration
// Learn more about configuration options: https://github.com/johnste/finicky/wiki/Configuration

export default {
  defaultBrowser: "Safari",
  options: {
    // Check for updates. Default: true
    checkForUpdates: true,
    // Log every request to file. Default: false
    logRequests: false,
    // Hide Finicky icon in menu bar. Default: false
    hideIcon: false,
  },
  handlers: [
    {
      match: [
        "docs.google.com*",
        "meet.google.com*",
      ],
      browser: "Google Chrome"
    }
  ]
}
