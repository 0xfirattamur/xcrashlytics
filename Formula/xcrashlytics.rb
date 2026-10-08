# Homebrew formula. `version` + `sha256` are bumped automatically by the
# release workflow (.github/workflows/release.yml) on each tagged release.
class Xcrashlytics < Formula
  desc "Firebase Crashlytics CLI with agent-readable JSON"
  homepage "https://github.com/0xfirattamur/xcrashlytics"
  version "0.2.0"
  url "https://github.com/0xfirattamur/xcrashlytics/releases/download/v#{version}/xcrashlytics-v#{version}-macos-universal.tar.gz"
  sha256 "f88024296206f15748728cf627305e673d82da772ffd75325f9d75f159f36b3c"
  license "MIT"

  depends_on :macos

  def install
    bin.install "xcrashlytics"
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/xcrashlytics --version").strip
  end
end
