function fixture() {
  return {
    "agency.txt":
      "agency_id,agency_name,agency_url,agency_timezone\n001,夕鉄バス,https://example.test,Asia/Tokyo\n",
    "stops.txt":
      "stop_id,stop_name,stop_lat,stop_lon,zone_id\n01,同名,43,141,A\n02,途中,43,141,B\n03,同名,43,141,C\n",
    "routes.txt":
      "route_id,agency_id,route_short_name,route_long_name,route_type\n01,001,R,路線,3\n",
    "calendar.txt":
      "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\n001,1,1,1,1,1,0,0,20260101,20261231\n",
    "calendar_dates.txt":
      "service_id,date,exception_type\n001,20260102,2\n001,20260103,1\n",
    "trips.txt": "route_id,service_id,trip_id\n01,001,0001\n",
    "stop_times.txt":
      "trip_id,arrival_time,departure_time,stop_id,stop_sequence,pickup_type,drop_off_type\n0001,24:10:01,24:10:31,01,0,0,1\n0001,24:20:00,24:21:00,02,1,0,0\n0001,25:00:00,25:00:00,03,2,1,0\n",
    "fare_attributes.txt":
      "fare_id,price,currency_type,payment_method,transfers\n001,500,JPY,0,0\n",
    "fare_rules.txt": "fare_id,route_id,origin_id,destination_id\n001,01,A,C\n",
  };
}
module.exports = { fixture };
