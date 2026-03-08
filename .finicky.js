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
  rewrite: [
    {
      // Redirect all x.com urls to use xcancel.com
      match: "x.com/*",
      url: (url) => {
        url.host = "xcancel.com";
        return url;
      },
    },
  ],
  handlers: [
    {
      match: [
        "docs.google.com*",
        "meet.google.com*",
      ],
      browser: {
        name: "Google Chrome",
        profile: "Personal"
      }
    },
    {
      match: [
        "*claude.ai*",
        "*google.com*",
      ],
      browser: {
        name: "Browserino",
      }
    },
    {
      match: [
        "localhost*",
      ],
      // url, options
      browser: (url, _) => ({
        name: "Google Chrome",
        profile: "Personal",
        args: ["--incognito", url.href]
      })
    }
  ]
}

