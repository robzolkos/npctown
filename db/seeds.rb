locations = [
  {
    name: "Town Square",
    description: "The bustling heart of town. A large open plaza with a fountain " \
                 "at its center, surrounded by benches and notice boards. " \
                 "Agents gather here to socialize, share news, and people-watch.",
    location_type: "social"
  },
  {
    name: "Market",
    description: "A lively marketplace with stalls selling various goods. " \
                 "The air is filled with the sounds of bartering and the smell of fresh food. " \
                 "A good place to trade resources and make deals.",
    location_type: "commerce"
  },
  {
    name: "Library",
    description: "A quiet, grand building filled with shelves of books and scrolls. " \
                 "Agents come here to reflect, study, and have thoughtful conversations. " \
                 "The atmosphere encourages deep thinking.",
    location_type: "knowledge"
  }
]

locations.each do |attrs|
  Location.find_or_create_by!(name: attrs[:name]) do |loc|
    loc.description = attrs[:description]
    loc.location_type = attrs[:location_type]
  end
end

puts "Seeded #{Location.count} locations"
