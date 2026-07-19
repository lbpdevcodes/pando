# frozen_string_literal: true

require "tmpdir"

RSpec.describe Pando::Settings do
  around do |example|
    Dir.mktmpdir do |dir|
      ENV["PANDO_ROOT"] = dir
      example.run
    ensure
      ENV.delete("PANDO_ROOT")
    end
  end

  it "round-trips values through the settings file" do
    described_class.save(theme: "nord")

    expect(described_class.load["theme"]).to eq("nord")
  end

  it "merges rather than clobbers, and tolerates a corrupt file" do
    described_class.save(theme: "nord")
    described_class.save(other: "x")
    expect(described_class.load["theme"]).to eq("nord")

    File.write(File.join(ENV["PANDO_ROOT"], "settings.json"), "{corrupt")
    expect(described_class.load).to eq({})
  end

  it "persists the selected theme across application boots without leaking secrets" do
    app = Pando::Application.new
    app.use_theme(:nord)

    raw = File.read(File.join(ENV["PANDO_ROOT"], "settings.json"))
    expect(JSON.parse(raw)).to eq({"theme" => "nord"})
    expect(raw).not_to include("seed", "signing", "encryption_key")
    expect(File.exist?(File.join(ENV["PANDO_ROOT"], "session.json"))).to be(false)

    expect(Pando::Application.new.session[:theme]).to eq(:nord)
  end
end
