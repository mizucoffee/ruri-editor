cask "ruri" do
  version :latest
  sha256 :no_check

  url "https://github.com/mizucoffee/ruri-editor/releases/download/homebrew-latest/ruri-macos-arm64.zip",
      verified: "github.com/mizucoffee/ruri-editor/"
  name "ruri"
  desc "Code review editor"
  homepage "https://github.com/mizucoffee/ruri-editor"

  depends_on macos: :tahoe
  depends_on arch:  :arm64

  app "Ruri.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Ruri.app"],
                   sudo: false
  end

  uninstall quit: "net.mizucoffee.ruri"
end
