# Homebrew formula. `version` + `sha256` are bumped automatically by the
# release workflow (.github/workflows/release.yml) on each tagged release.
class Xcrashlytics < Formula
  desc "Firebase Crashlytics CLI with agent-readable JSON"
  homepage "https://github.com/0xfirattamur/xcrashlytics"
  version "0.0.0"
  url "https://github.com/0xfirattamur/xcrashlytics/releases/download/v#{version}/xcrashlytics-v#{version}-macos-universal.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  depends_on :macos

  def install
    bin.install "xcrashlytics"
  end

  test do
    assert_match "xcrashlytics", shell_output("#{bin}/xcrashlytics --help")
  end
end
