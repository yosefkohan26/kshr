cask "kshr" do
  version "0.62.1"
  sha256 "3be67bc3600fdde1c2b62c02c448235bd81ad0bf0772ff33353a6d91cc4b19fe"

  url "https://github.com/yosefkohan26/kshr/releases/download/v#{version}/kshr-macos.dmg"
  name "kshr"
  desc "Lightweight native macOS terminal with vertical tabs for AI coding agents"
  homepage "https://kshr.dev"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "kshr.app"
  binary "#{appdir}/kshr.app/Contents/Resources/bin/kshr"

  zap trash: [
    "~/Library/Application Support/kshr",
    "~/Library/Caches/kshr",
    "~/Library/Preferences/ai.yosefkohan26.kshrterm.plist",
  ]
end
