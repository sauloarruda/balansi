require "rails_helper"

RSpec.describe BrowserTimezone, type: :controller do
  include_context "controller concern test"

  describe "included behavior" do
    it "adds detect_browser_timezone as a helper method" do
      expect(controller.class.helpers).to respond_to(:detect_browser_timezone)
    end
  end

  describe "#detect_browser_timezone" do
    it "returns timezone from cookie when present" do
      request.cookies[:timezone] = "America/New_York"
      get :index
      expect(controller.send(:detect_browser_timezone)).to eq("America/New_York")
    end

    describe "defaults to America/Sao_Paulo" do
      [
        [ nil, "when cookie not present" ],
        [ "", "when cookie is blank" ]
      ].each do |cookie_value, description|
        it description do
          request.cookies[:timezone] = cookie_value
          get :index
          expect(controller.send(:detect_browser_timezone)).to eq("America/Sao_Paulo")
        end
      end

      it "when cookie key is missing" do
        get :index
        expect(controller.send(:detect_browser_timezone)).to eq("America/Sao_Paulo")
      end
    end

    describe "edge cases" do
      it "returns cookie value without validation" do
        request.cookies[:timezone] = "Custom/Timezone"
        get :index
        expect(controller.send(:detect_browser_timezone)).to eq("Custom/Timezone")
      end

      it "handles timezone with special characters" do
        request.cookies[:timezone] = "UTC+5:30"
        get :index
        expect(controller.send(:detect_browser_timezone)).to eq("UTC+5:30")
      end

      it "handles very long timezone string" do
        long_timezone = "A" * 200
        request.cookies[:timezone] = long_timezone
        get :index
        expect(controller.send(:detect_browser_timezone)).to eq(long_timezone)
      end

      it "handles timezone with unicode characters" do
        request.cookies[:timezone] = "America/São_Paulo"
        get :index
        expect(controller.send(:detect_browser_timezone)).to eq("America/São_Paulo")
      end
    end
  end
end
