provider "google"{
	credentials=file(var.credentials)
	project=var.projectName
	region=var.regionName
  	zone=var.zoneName
}

resource "google_compute_network" "test-vpc"{
	name="test-vpc"
	auto_create_subnetworks="false"
}

resource "google_compute_subnetwork" "test-subnet"{
	name="test-subnet"
	network=google_compute_network.test-vpc.name
	ip_cidr_range="10.0.16.0/24"
}

resource "google_compute_firewall" "test-vpc-http"{
	name="test-vpc-http"
	network=google_compute_network.test-vpc.name
	allow{
		protocol="tcp"
		ports=[80,443,22]
	}
	target_tags=["apache-server"]
}

resource "google_compute_instance" "apache"{
	name="apache-server"
	machine_type="f1-micro"
	boot_disk{
		initialize_params{
			image="ubuntu-1804-lts"
		}
	}
	network_interface{
		network=google_compute_network.test-vpc.name
		subnetwork=google_compute_subnetwork.test-subnet.name
		access_config{

		}
	}
	tags=["apache-server"]
	metadata_startup_script="sudo apt-get update;sudo apt-get install apache2 -y;sudo systemctl start apache2"
}

resource "google_compute_firewall" "test-vpc-ssh"{
	name="test-vpc-ssh"
	network=google_compute_network.test-vpc.name
	allow{
		protocol="tcp"
		ports=[22]
	}
	target_tags=["proxy-server"]
}

resource "google_compute_instance" "proxy-server"{
	name="proxy-server"
	machine_type="f1-micro"
	boot_disk{
		initialize_params{
			image="ubuntu-1804-lts"
		}
	}
	network_interface{
		network=google_compute_network.test-vpc.name
		subnetwork=google_compute_subnetwork.test-subnet.name
	}
 	metadata_startup_script="sudo apt-get install postgresql-client -y"
	tags=["proxy-server"]
}

resource "google_compute_global_address" "private_ip_address" {

  name          = "private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.test-vpc.self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {

  network                 = google_compute_network.test-vpc.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "random_id" "db_name_suffix1" {
  byte_length = 4
}

resource "random_id" "db_name_suffix2" {
  byte_length = 4
}

resource "google_sql_database_instance" "db-instance1" {

  name   = "private-instance-${random_id.db_name_suffix1.hex}"
  region=var.regionName
  database_version = "POSTGRES_9_6"
  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.test-vpc.self_link
    }
  }
}

resource "google_sql_database_instance" "db-instance2" {

  name   = "private-instance-${random_id.db_name_suffix2.hex}"
  region=var.regionName
  database_version = "POSTGRES_9_6"
  depends_on = [google_service_networking_connection.private_vpc_connection , google_sql_database_instance.db-instance1]

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.test-vpc.self_link
    }
  }
}

resource "google_compute_router" "nat-router"{
	name="nat-router"
	region=var.regionName
	network=google_compute_network.test-vpc.self_link
	bgp{
		asn=65000
	}
}

resource "google_compute_router_nat" "test-nat"{
	name="test-nat"
	region=var.regionName
	router=google_compute_router.nat-router.name
	nat_ip_allocate_option="AUTO_ONLY"
	source_subnetwork_ip_ranges_to_nat="ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_container_cluster" "primary" {
  name     = "test-gke-cluster"
  #location = "us-central1"
  remove_default_node_pool = true
  initial_node_count       = 3

  master_auth {
    username = ""
    password = ""

    client_certificate_config {
      issue_client_certificate = false
    }
  }
  network = google_compute_network.test-vpc.self_link
  subnetwork=google_compute_subnetwork.test-subnet.name
}

resource "google_container_node_pool" "primary_preemptible_nodes" {
  name       = "my-node-pool"
  #location   = "us-central1"
  cluster    = google_container_cluster.primary.name
  node_count = 3

  node_config {
    preemptible  = true
    machine_type = "f1-micro"

    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }
}

resource "google_storage_bucket" "test-bucket" {
  name     = "bucket-${random_id.db_name_suffix2.hex}"
}