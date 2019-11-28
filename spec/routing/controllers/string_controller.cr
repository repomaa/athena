struct StringController < Athena::Routing::Controller
  @[Athena::Routing::Get(path: "string/:val")]
  def string(val : String) : String
    val.should be_a String
    val.should eq "sdfsd"
    val
  end

  @[Athena::Routing::Post(path: "string")]
  def string_post(body : String) : String
    body.should be_a String
    body.should eq "sdfsd"
    body
  end

  @[Athena::Routing::Post(path: "json/string")]
  def json_string_post(body : String) : JSON::Any
    JSON.parse(body)
  end
end
