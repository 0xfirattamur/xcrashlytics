# Homebrew formula. `version` + `sha256` are bumped automatically by the
# release workflow (.github/workflows/release.yml) on each tagged release.
class Xcrashlytics < Formula
  desc "Firebase Crashlytics CLI with agent-readable JSON"
  homepage "https://github.com/0xfirattamur/xcrashlytics"
  version "0.1.0"
  url "https://github.com/0xfirattamur/xcrashlytics/releases/download/v#{version}/xcrashlytics-v#{version}-macos-universal.tar.gz"
  sha256 "105a4785f6233bf449ec9a5709a7c1ffbdf1ea6f166ea124684e15b1b4aba9c5"
  license "MIT"

  depends_on :macos

  def install
    bin.install "xcrashlytics"
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/xcrashlytics --version").strip
  end
end
