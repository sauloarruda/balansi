require "rails_helper"

RSpec.describe BrowserLanguage, type: :controller do
  include_context "controller concern test"

  describe "included behavior" do
    it "adds detect_browser_language as a helper method" do
      expect(controller.class.helpers).to respond_to(:detect_browser_language)
    end

    it "sets locale before each action via before_action" do
      request.headers["Accept-Language"] = "en-US"
      get :index
      expect(I18n.locale).to eq(:en)
    end
  end

  describe "#detect_browser_language" do
    it "returns :pt for pt-BR Accept-Language header" do
      request.headers["Accept-Language"] = "pt-BR,pt;q=0.9,en;q=0.8"
      get :index
      expect(controller.send(:detect_browser_language)).to eq(:pt)
    end

    it "returns :pt for pt Accept-Language header" do
      request.headers["Accept-Language"] = "pt,en;q=0.9"
      get :index
      expect(controller.send(:detect_browser_language)).to eq(:pt)
    end

    it "returns :pt for pt-PT Accept-Language header" do
      request.headers["Accept-Language"] = "pt-PT,en;q=0.9"
      get :index
      expect(controller.send(:detect_browser_language)).to eq(:pt)
    end

    it "returns :en for en Accept-Language header" do
      request.headers["Accept-Language"] = "en-US,en;q=0.9"
      get :index
      expect(controller.send(:detect_browser_language)).to eq(:en)
    end

    it "returns :en for en-GB Accept-Language header" do
      request.headers["Accept-Language"] = "en-GB,en;q=0.9"
      get :index
      expect(controller.send(:detect_browser_language)).to eq(:en)
    end

    describe "defaults to :pt" do
      [
        [ nil, "when Accept-Language header is blank" ],
        [ "", "when Accept-Language header is empty string" ],
        [ "fr-FR,fr;q=0.9", "for unknown language" ],
        [ "es-ES,es;q=0.9", "for Spanish language" ]
      ].each do |header_value, description|
        it description do
          request.headers["Accept-Language"] = header_value
          get :index
          expect(controller.send(:detect_browser_language)).to eq(:pt)
        end
      end
    end

    it "prefers pt over en when both present" do
      request.headers["Accept-Language"] = "pt-BR,en;q=0.9"
      get :index
      expect(controller.send(:detect_browser_language)).to eq(:pt)
    end

    it "handles Accept-Language header with quality values" do
      request.headers["Accept-Language"] = "en;q=0.8,pt;q=0.9"
      get :index
      expect(controller.send(:detect_browser_language)).to eq(:pt)
    end

    it "handles Accept-Language header with spaces" do
      request.headers["Accept-Language"] = "pt-BR, pt;q=0.9, en;q=0.8"
      get :index
      expect(controller.send(:detect_browser_language)).to eq(:pt)
    end

    describe "edge cases" do
      it "handles malformed Accept-Language header with special characters" do
        request.headers["Accept-Language"] = "pt-BR;q=invalid,en;q=0.9"
        get :index
        # Should still parse and detect pt
        expect(controller.send(:detect_browser_language)).to eq(:pt)
      end

      it "handles Accept-Language header with unicode characters" do
        request.headers["Accept-Language"] = "pt-BR,en;q=0.9"
        get :index
        expect(controller.send(:detect_browser_language)).to eq(:pt)
      end

      it "handles Accept-Language header with only semicolons" do
        request.headers["Accept-Language"] = ";;;"
        get :index
        # Should default to :pt when parsing fails
        expect(controller.send(:detect_browser_language)).to eq(:pt)
      end

      it "handles Accept-Language header with newlines" do
        request.headers["Accept-Language"] = "pt-BR\n,en;q=0.9"
        get :index
        # Should handle newlines gracefully
        expect(controller.send(:detect_browser_language)).to eq(:pt)
      end

      it "handles very long Accept-Language header" do
        long_header = "pt-BR," + ("en;q=0.9," * 100)
        request.headers["Accept-Language"] = long_header
        get :index
        expect(controller.send(:detect_browser_language)).to eq(:pt)
      end

      it "handles Accept-Language header with empty language codes" do
        request.headers["Accept-Language"] = ",,pt-BR,,en,"
        get :index
        expect(controller.send(:detect_browser_language)).to eq(:pt)
      end
    end

    describe "database priority for authenticated users" do
      let(:user) { create(:user, language: "en") }

      before do
        session[:user_id] = user.id
      end

      it "always uses database language for authenticated users, ignoring Accept-Language header" do
        user.update(language: "pt")
        request.headers["Accept-Language"] = "en-US"

        get :index
        expect(controller.send(:detect_browser_language)).to eq(:pt)
        expect(I18n.locale).to eq(:pt)
      end

      it "uses database language even when Accept-Language suggests different language" do
        user.update(language: "en")
        request.headers["Accept-Language"] = "pt-BR"

        get :index
        expect(controller.send(:detect_browser_language)).to eq(:en)
        expect(I18n.locale).to eq(:en)
      end

      it "preserves language across requests via database for authenticated users" do
        user.update(language: "pt")
        request.headers["Accept-Language"] = "en-US"

        # First request should use database
        get :index
        expect(controller.send(:detect_browser_language)).to eq(:pt)
        expect(I18n.locale).to eq(:pt)

        # Second request should still use database
        get :index
        expect(controller.send(:detect_browser_language)).to eq(:pt)
        expect(I18n.locale).to eq(:pt)
      end

      it "ignores URL parameter and uses database language" do
        user.update(language: "en")
        request.headers["Accept-Language"] = "pt-BR"

        get :index, params: { language: "pt" }
        # Should still use database, not URL parameter
        expect(controller.send(:detect_browser_language)).to eq(:en)
        expect(I18n.locale).to eq(:en)
      end

      it "falls back to Accept-Language header if database has invalid locale" do
        user.update(language: "invalid")
        request.headers["Accept-Language"] = "en-US"

        get :index
        # Should fall back to header when DB has invalid locale
        expect(controller.send(:detect_browser_language)).to eq(:en)
        expect(I18n.locale).to eq(:en)
      end
    end
  end

  describe "#set_locale" do
    it "sets I18n.locale based on browser language" do
      request.headers["Accept-Language"] = "en-US"
      get :index
      expect(I18n.locale).to eq(:en)
    end

    it "sets I18n.locale to :pt when browser language is pt" do
      request.headers["Accept-Language"] = "pt-BR"
      get :index
      expect(I18n.locale).to eq(:pt)
    end

    it "sets I18n.locale to default locale when detect_browser_language returns nil" do
      allow(controller).to receive(:detect_browser_language).and_return(nil)
      get :index
      expect(I18n.locale).to eq(I18n.default_locale)
    end
  end
end
