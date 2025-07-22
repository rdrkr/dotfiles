// Use https://finicky-kickstart.now.sh to generate basic configuration
// Learn more about configuration options: https://github.com/johnste/finicky/wiki/Configuration

export default {
  defaultBrowser: "Safari",
  handlers: [
    {
      match: [
        "meet.google.com*",
      ],
      browser: "Google Chrome"
    }
  ]
}
