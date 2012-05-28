require 'sinatra'
require 'net/http'
require 'nokogiri'
require 'json'
require 'sequel'
require 'mysql'

DB = Sequel.connect(ENV['DATABASE_URL'] || 'mysql://root:@127.0.0.1:3306/trainsharing')

routes = DB[:routes] # Create a routes dataset

get '/' do
  "Hi, this is just the scraper for <a href='http://trainshare.ch'>trainshare</a>"
end

get '/:train_id' do

  # check if train_id is really not in the database
  results = routes.filter(:linename => params[:train_id])

  if results.count == 0

    # this_train_id = "S2 18246"
    post_url = "http://fahrplan.sbb.ch/bin/trainsearch.exe/dn?"

    # make post request
    uri = URI(post_url)
    res = Net::HTTP.post_form(uri, 'trainname' => params[:train_id])

    # parse response and extract url to details page of that train line.
    doc = Nokogiri::HTML(res.body)
    train_url = nil

    # Get the train line number
    for a in doc.search("div.hafas div.hac_greybox table.hfs_trainsearch a")
      train_url = a.attributes["href"]
    end


    # fetch the train_url page
    uri = URI(train_url)
    res = Net::HTTP.get(uri)

    doc = Nokogiri::HTML(res)

    last_dep_station = nil
    last_dep_time = nil

    train_number = nil

    # Get train line number.    
    for div in doc.search("div.hafas div.hac_greybox div b")
      train_number = div.children.text
      puts train_number
    end

    for tr in doc.search("table.hfs_traininfo tr")
      if tr.attributes["class"] != nil and tr.search("td.location a")[0] != nil
        if last_dep_station != nil and last_dep_time != nil # has already a starting station

          current_station = tr.search("td.location a")[0].children.text

          routes.insert(
            :linename => train_number,
            :dep_station => last_dep_station,
            :dep_time => last_dep_time,
            :arr_station => current_station,
            :arr_time => tr.search("td.arr.time")[0].children.text.gsub(/\n/, "")
          )

          puts current_station

          last_dep_station = current_station
          last_dep_time = tr.search("td.dep.time")[0].children.text.gsub(/\n/, "")

        else
          last_dep_station = tr.search("td.location a")[0].children.text
          last_dep_time = tr.search("td.dep.time")[0].children.text.gsub(/\n/, "")
        end
      end
    end

    content_type :json
    { :message => 'inserted' }.to_json

  else

    content_type :json
    { :message => 'exists' }.to_json

  end
end