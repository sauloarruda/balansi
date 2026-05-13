require "base64"
require "stringio"

FactoryBot.define do
  factory :image do
    association :recipe
    position { 0 }

    after(:build) do |image|
      image.file.attach(
        io: StringIO.new(Base64.decode64(
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        )),
        filename: "recipe.png",
        content_type: "image/png"
      )
    end
  end
end
