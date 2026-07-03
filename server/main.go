package main

import (
	"strconv"
	"time"

	"github.com/cdesiniotis/chord"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

func Create(cfg *chord.Config) error {
	chord.CreateChord(cfg)
	return nil
}

func Join(cfg *chord.Config, ip string, port int) error {
	_, err := chord.JoinChord(cfg, ip, port)
	return err
}

func JoinNNodes(cfg *chord.Config, numNodes int) ([]*chord.Node, error) {
	nodes := make([]*chord.Node, numNodes)

	// Bootstrap node
	log.Infof("Starting bootstrap node on %s:%d", cfg.Addr, cfg.Port)
	bootstrap := chord.CreateChord(cfg)
	nodes[0] = bootstrap

	baseIP := cfg.Addr
	basePort := int(cfg.Port)

	for i := 1; i < numNodes; i++ {
		port := basePort + i
		newCfg := *cfg
		newCfg.Port = uint32(port)

		log.Infof("Starting node on port %d joining bootstrap %s:%d", port, baseIP, basePort)

		// Create and join to bootstrap
		node, err := chord.JoinChord(&newCfg, baseIP, basePort)
		if err != nil {
			log.Errorf("error joining node on port %d: %v", port, err)
			return nil, err
		}
		nodes[i] = node

		// Small delay to let the node come up
		time.Sleep(200 * time.Millisecond)
	}

	return nodes, nil
}

func readConfig(filename string, defaults map[string]interface{}) (*viper.Viper, error) {
	v := viper.New()
	for key, value := range defaults {
		v.SetDefault(key, value)
	}
	v.SetConfigName(filename) // name of config file without extensions
	v.AddConfigPath(".")
	v.AddConfigPath("./server")
	v.AutomaticEnv()
	err := v.ReadInConfig()
	return v, err
}

func defaults() map[string]interface{} {
	return map[string]interface{}{
		"keysize":                  8,
		"addr":                     "0.0.0.0",
		"port":                     8000,
		"timeout":                  2000,
		"stabilizeinterval":        250,
		"fixfingerinterval":        50,
		"checkpredecessorinterval": 150,
		"successorlistsize":        2,
		"logging":                  true,
		"enablemetrics":            false,
		"metricsoutputdir":         "metrics",
	}
}

func main() {

	// read config file; if missing, continue with defaults (allow CLI flags)
	v, err := readConfig("config", defaults())
	if err != nil {
		log.Warnf("could not read config file: %v -- continuing with defaults and CLI flags", err)
		v = viper.New()
		for k, val := range defaults() {
			v.SetDefault(k, val)
		}
	}

	// unmarshal to chord config struct
	var cfg *chord.Config
	err = v.Unmarshal(&cfg)
	if err != nil {
		log.Fatalf("error unmarshalling config: %v\n", err)
	}
	cfg = chord.SetDefaultGrpcOpts(cfg)

	var cmdCreate = &cobra.Command{
		Use:   "create",
		Short: "Create a new chord dht ring",
		Long:  `create is for creating a new chord distributed hash table`,
		Args:  cobra.ExactArgs(0),
		Run: func(cmd *cobra.Command, args []string) {
			err := Create(cfg)
			if err != nil {
				log.Fatalf("error calling Create(cfg): %v\n", err)
			}
			for {
				time.Sleep(5 * time.Second)
			}
		},
	}

	var cmdJoin = &cobra.Command{
		Use:   "join [ip] [port]",
		Short: "Join an existing chord dht ring",
		Long:  `join is for joining an existing chord dht ring by contacting the node at ip:port`,
		Args:  cobra.ExactArgs(2),
		Run: func(cmd *cobra.Command, args []string) {
			port, err := strconv.Atoi(args[1])
			if err != nil {
				log.Fatalf("port field in config is not valid\n")
			}

			// Allow overriding listening address/port via flags
			nodeAddr, _ := cmd.Flags().GetString("addr")
			nodePort, _ := cmd.Flags().GetInt("port")

			localCfg := *cfg
			if nodeAddr != "" {
				localCfg.Addr = nodeAddr
			}
			if nodePort != 0 {
				localCfg.Port = uint32(nodePort)
			}

			err = Join(&localCfg, args[0], port)
			if err != nil {
				log.Fatalf("error calling Join(cfg, ip, port): %v\n", err)
			}
			for {
				time.Sleep(5 * time.Second)
			}
		},
	}
	// flags local al comando join para especificar addr/port del nodo que se crea
	cmdJoin.Flags().String("addr", "", "Address to bind the joining node to (overrides config)")
	cmdJoin.Flags().Int("port", 0, "Port to bind the joining node to (overrides config)")

	var cmdJoinNNodes = &cobra.Command{
		Use: "join-n-nodes [num-nodes]",
		Short: "Join multiple nodes to an existing chord dht ring",
		Long:  `join-n-nodes is for create n logical nodes using ports starting from config`,
		Args: cobra.ExactArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			numNodes, err := strconv.Atoi(args[0])
			if err != nil {
				log.Fatalf("num-nodes argument is not valid\n")
			}

			// Allow overriding base addr/port via flags
			nodeAddr, _ := cmd.Flags().GetString("addr")
			nodePort, _ := cmd.Flags().GetInt("port")

			localCfg := *cfg
			if nodeAddr != "" {
				localCfg.Addr = nodeAddr
			}
			if nodePort != 0 {
				localCfg.Port = uint32(nodePort)
			}

			_, err = JoinNNodes(&localCfg, numNodes)
			if err != nil {
				log.Fatalf("error calling JoinNNodes(cfg, numNodes): %v\n", err)
			}
			for {
				time.Sleep(5 * time.Second)
			}
		},
	}
	cmdJoinNNodes.Flags().String("addr", "", "Base address to bind nodes to (overrides config)")
	cmdJoinNNodes.Flags().Int("port", 0, "Base port to start creating nodes from (overrides config)")

	var rootCmd = &cobra.Command{Use: "chord"}

	//flags globales
	rootCmd.PersistentFlags().String("addr", "0.0.0.0", "Address to bind to")
	rootCmd.PersistentFlags().Int("port", 8000, "Port to bind to")

	rootCmd.AddCommand(cmdCreate, cmdJoin, cmdJoinNNodes)
	rootCmd.Execute()
}
