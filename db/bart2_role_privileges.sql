-- MySQL dump 10.13  Distrib 5.1.54, for debian-linux-gnu (i686)
--
-- Host: localhost    Database: openmrs17
-- ------------------------------------------------------
-- Server version	5.1.54-1ubuntu4

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `role_privilege`
--


--
-- Dumping data for table `role_privilege`
--

LOCK TABLES `role_privilege` WRITE;
/*!40000 ALTER TABLE `role_privilege` DISABLE KEYS */;
INSERT INTO `role_privilege` VALUES ('System Developer','Manage appointments'),('System Developer','Manage ART adherence'),('System Developer','Manage ART visits'),('System Developer','Manage drug dispensations'),('System Developer','Manage HIV first visits'),('System Developer','Manage HIV reception visits'),('System Developer','Manage HIV staging visits'),('System Developer','Manage Patient Programs'),('System Developer','Manage pre ART visits'),('System Developer','Manage prescriptions'),('System Developer','Manage Relationships'),('System Developer','Manage TB reception visit'),('System Developer','Manage Vitals');


INSERT INTO `role_privilege` VALUES ('Registration Clerk','Manage appointments'),('Registration Clerk','Manage ART adherence'),('Registration Clerk','Manage ART visits'),('Registration Clerk','Manage drug dispensations'),('Registration Clerk','Manage HIV first visits'),('Registration Clerk','Manage HIV reception visits'),('Registration Clerk','Manage HIV staging visits'),('Registration Clerk','Manage Patient Programs'),('Registration Clerk','Manage pre ART visits'),('Registration Clerk','Manage prescriptions'),('Registration Clerk','Manage Relationships'),('Registration Clerk','Manage TB reception visit'),('Registration Clerk','Manage Vitals');

INSERT INTO `role_privilege` VALUES ('Vitals Clerk','Manage appointments'),('Vitals Clerk','Manage ART adherence'),('Vitals Clerk','Manage ART visits'),('Vitals Clerk','Manage drug dispensations'),('Vitals Clerk','Manage HIV first visits'),('Vitals Clerk','Manage HIV reception visits'),('Vitals Clerk','Manage HIV staging visits'),('Vitals Clerk','Manage Patient Programs'),('Vitals Clerk','Manage pre ART visits'),('Vitals Clerk','Manage prescriptions'),('Vitals Clerk','Manage Relationships'),('Vitals Clerk','Manage TB reception visit'),('Vitals Clerk','Manage Vitals');

INSERT INTO `role_privilege` VALUES ('Nurse','Manage appointments'),('Nurse','Manage ART adherence'),('Nurse','Manage ART visits'),('Nurse','Manage drug dispensations'),('Nurse','Manage HIV first visits'),('Nurse','Manage HIV reception visits'),('Nurse','Manage HIV staging visits'),('Nurse','Manage Patient Programs'),('Nurse','Manage pre ART visits'),('Nurse','Manage prescriptions'),('Nurse','Manage Relationships'),('Nurse','Manage TB reception visit'),('Nurse','Manage Vitals');

INSERT INTO `role_privilege` VALUES ('Clinician','Manage appointments'),('Clinician','Manage ART adherence'),('Clinician','Manage ART visits'),('Clinician','Manage drug dispensations'),('Clinician','Manage HIV first visits'),('Clinician','Manage HIV reception visits'),('Clinician','Manage HIV staging visits'),('Clinician','Manage Patient Programs'),('Clinician','Manage pre ART visits'),('Clinician','Manage prescriptions'),('Clinician','Manage Relationships'),('Clinician','Manage TB reception visit'),('Clinician','Manage Vitals');

INSERT INTO `role_privilege` VALUES ('Pharmacist','Manage appointments'),('Pharmacist','Manage ART adherence'),('Pharmacist','Manage ART visits'),('Pharmacist','Manage drug dispensations'),('Pharmacist','Manage HIV first visits'),('Pharmacist','Manage HIV reception visits'),('Pharmacist','Manage HIV staging visits'),('Pharmacist','Manage Patient Programs'),('Pharmacist','Manage pre ART visits'),('Pharmacist','Manage prescriptions'),('Pharmacist','Manage Relationships'),('Pharmacist','Manage TB reception visit'),('Pharmacist','Manage Vitals');

INSERT INTO `role_privilege` VALUES ('Provider','Manage appointments'),('Provider','Manage ART adherence'),('Provider','Manage ART visits'),('Provider','Manage drug dispensations'),('Provider','Manage HIV first visits'),('Provider','Manage HIV reception visits'),('Provider','Manage HIV staging visits'),('Provider','Manage Patient Programs'),('Provider','Manage pre ART visits'),('Provider','Manage prescriptions'),('Provider','Manage Relationships'),('Provider','Manage TB reception visit'),('Provider','Manage Vitals');

INSERT INTO `role_privilege` VALUES ('Superuser','Manage appointments'),('Superuser','Manage ART adherence'),('Superuser','Manage ART visits'),('Superuser','Manage drug dispensations'),('Superuser','Manage HIV first visits'),('Superuser','Manage HIV reception visits'),('Superuser','Manage HIV staging visits'),('Superuser','Manage Patient Programs'),('Superuser','Manage pre ART visits'),('Superuser','Manage prescriptions'),('Superuser','Manage Relationships'),('Superuser','Manage TB reception visit'),('Superuser','Manage Vitals');

INSERT INTO `role_privilege` VALUES ('General Registration Clerk','Manage appointments'),('General Registration Clerk','Manage ART adherence'),('General Registration Clerk','Manage ART visits'),('General Registration Clerk','Manage drug dispensations'),('General Registration Clerk','Manage HIV first visits'),('General Registration Clerk','Manage HIV reception visits'),('General Registration Clerk','Manage HIV staging visits'),('General Registration Clerk','Manage Patient Programs'),('General Registration Clerk','Manage pre ART visits'),('General Registration Clerk','Manage prescriptions'),('General Registration Clerk','Manage Relationships'),('General Registration Clerk','Manage TB reception visit'),('General Registration Clerk','Manage Vitals');

INSERT INTO `role_privilege` VALUES ('Data Assistant','Manage appointments'),('Data Assistant','Manage ART adherence'),('Data Assistant','Manage ART visits'),('Data Assistant','Manage drug dispensations'),('Data Assistant','Manage HIV first visits'),('Data Assistant','Manage HIV reception visits'),('Data Assistant','Manage HIV staging visits'),('Data Assistant','Manage Patient Programs'),('Data Assistant','Manage pre ART visits'),('Data Assistant','Manage prescriptions'),('Data Assistant','Manage Relationships'),('Data Assistant','Manage TB reception visit'),('Data Assistant','Manage Vitals');

/*!40000 ALTER TABLE `role_privilege` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2011-08-11 10:36:37
